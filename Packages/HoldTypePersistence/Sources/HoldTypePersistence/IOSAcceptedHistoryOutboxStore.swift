import Foundation

struct IOSAcceptedHistoryOutboxStoreIdentity: Equatable, Sendable {
    private let value = UUID()
}

extension IOSAcceptedHistoryOutboxStoreIdentity:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryOutboxStoreIdentity(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSAcceptedHistoryOutboxGuardedBaselineEvidence: Sendable {
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    fileprivate init(
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) {
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }
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
              marker.state.isPendingDecision,
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
              marker.state.isPendingDecision,
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
    let storeIdentity: IOSAcceptedHistoryOutboxStoreIdentity
    let deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    func provesMembershipForDeliveryRemoval(
        for delivery: IOSAcceptedOutputDeliveryAuthorization
    ) -> Bool {
        guard case .delivery(let originatingDelivery) = origin,
              originatingDelivery == delivery,
              delivery.storeIdentity == deliveryStoreIdentity,
              capabilityOwnerIdentity
                == delivery.capabilityOwnerIdentity else {
            return false
        }
        return confirmedEntryForAcceptedDecision() != nil
    }

    func provesMembership(
        for observation: IOSAcceptedHistoryOutboxObservation
    ) -> Bool {
        guard case .observation(let originatingObservation) = origin,
              originatingObservation == observation,
              storeIdentity == observation.storeIdentity,
              capabilityOwnerIdentity
                == observation.capabilityOwnerIdentity,
              provesHeadMembership() else {
            return false
        }
        return confirmedEntryForAcceptedDecision() != nil
    }

    func provesHeadMembership(
        for observation: IOSAcceptedHistoryOutboxObservation
    ) -> Bool {
        provesMembership(for: observation)
    }

    func provesHeadMembership() -> Bool {
        guard let head = snapshot.envelope.entries.first else { return false }
        return head.hasSameImmutableBytes(as: entry)
            && confirmedEntryForAcceptedDecision() != nil
    }

    func deliveryRelation(
        to authorization: IOSAcceptedOutputDeliveryAuthorization
    ) -> IOSAcceptedHistoryOutboxDeliveryRelation {
        guard authorization.storeIdentity == deliveryStoreIdentity,
              let entry = confirmedEntryForAcceptedDecision() else {
            return .collision
        }
        return entry.deliveryRelation(to: authorization)
    }

    func confirmedEntryForAcceptedDecision()
        -> IOSAcceptedHistoryOutboxEntry? {
        let originatingEntry: IOSAcceptedHistoryOutboxEntry
        switch origin {
        case .delivery(let delivery):
            guard delivery.storeIdentity == deliveryStoreIdentity,
                  let expected = try? IOSAcceptedHistoryOutboxCandidate.entry(
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
    let storeIdentity: IOSAcceptedHistoryOutboxStoreIdentity
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    var isHead: Bool {
        snapshot.envelope.entries.first?.hasSameImmutableBytes(as: entry)
            == true
    }

    fileprivate init(
        entry: IOSAcceptedHistoryOutboxEntry,
        snapshot: IOSAcceptedHistoryOutboxJournalSnapshot,
        storeIdentity: IOSAcceptedHistoryOutboxStoreIdentity,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) {
        self.entry = entry
        self.snapshot = snapshot
        self.storeIdentity = storeIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
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

struct IOSAcceptedHistoryOutboxTemporalReceipt: Equatable, Sendable {
    let temporalState: IOSAcceptedHistoryOutboxTemporalState
    let membership: IOSAcceptedHistoryOutboxReceipt
    private let head: IOSAcceptedHistoryOutboxEntry
    private let snapshot: IOSAcceptedHistoryOutboxJournalSnapshot
    let storeIdentity: IOSAcceptedHistoryOutboxStoreIdentity
    let capabilityOwnerIdentity:
        IOSAcceptedHistoryCapabilityOwnerIdentity

    fileprivate init(
        temporalState: IOSAcceptedHistoryOutboxTemporalState,
        membership: IOSAcceptedHistoryOutboxReceipt,
        head: IOSAcceptedHistoryOutboxEntry,
        snapshot: IOSAcceptedHistoryOutboxJournalSnapshot,
        storeIdentity: IOSAcceptedHistoryOutboxStoreIdentity,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) {
        self.temporalState = temporalState
        self.membership = membership
        self.head = head
        self.snapshot = snapshot
        self.storeIdentity = storeIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }

    fileprivate func provesClassification(
        for membership: IOSAcceptedHistoryOutboxReceipt,
        storeIdentity: IOSAcceptedHistoryOutboxStoreIdentity,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) -> Bool {
        self.membership == membership
            && self.storeIdentity == storeIdentity
            && self.capabilityOwnerIdentity == capabilityOwnerIdentity
            && membership.storeIdentity == storeIdentity
            && membership.capabilityOwnerIdentity == capabilityOwnerIdentity
            && membership.snapshot == snapshot
            && snapshot.envelope.entries.first?.hasSameImmutableBytes(
                as: head
            ) == true
            && membership.entry.hasSameImmutableBytes(as: head)
            && membership.provesHeadMembership()
    }
}

extension IOSAcceptedHistoryOutboxTemporalReceipt:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryOutboxTemporalReceipt(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization:
    Equatable,
    Sendable {
    private enum ObservedOutboxSnapshot: Equatable, Sendable {
        case missing
        case existing(IOSAcceptedHistoryOutboxJournalSnapshot)
    }

    private let authorization: IOSAcceptedOutputDeliveryAuthorization
    private let observedOutboxSnapshot: ObservedOutboxSnapshot
    private let outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity
    private let pairedDeliveryStoreIdentity:
        IOSAcceptedOutputDeliveryStoreIdentity
    private let capabilityOwnerIdentity:
        IOSAcceptedHistoryCapabilityOwnerIdentity
    private let operationLeaseAuthorization:
        IOSPersistenceOperationLeaseAuthorization

    fileprivate init(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        observedOutboxSnapshot: IOSAcceptedHistoryOutboxJournalSnapshot?,
        outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) {
        self.authorization = authorization
        self.observedOutboxSnapshot = if let observedOutboxSnapshot {
            .existing(observedOutboxSnapshot)
        } else {
            .missing
        }
        self.outboxStoreIdentity = outboxStoreIdentity
        pairedDeliveryStoreIdentity = deliveryStoreIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.operationLeaseAuthorization = operationLeaseAuthorization
    }

    func provesAbsence(
        for authorization: IOSAcceptedOutputDeliveryAuthorization,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity,
        outboxStoreIdentity: IOSAcceptedHistoryOutboxStoreIdentity,
        ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> Bool {
        self.authorization == authorization
            && pairedDeliveryStoreIdentity == deliveryStoreIdentity
            && self.outboxStoreIdentity == outboxStoreIdentity
            && capabilityOwnerIdentity == ownerIdentity
            && authorization.capabilityOwnerIdentity == ownerIdentity
            && authorization.storeIdentity == deliveryStoreIdentity
            && self.operationLeaseAuthorization.provesSameActiveLease(
                as: operationLeaseAuthorization
            )
    }
}

extension IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

enum IOSAcceptedHistoryOutboxDeliveryAbsenceDisposition:
    Equatable,
    Sendable {
    case absent(IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization)
    case matching
    case collision
}

extension IOSAcceptedHistoryOutboxDeliveryAbsenceDisposition:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSAcceptedHistoryOutboxDeliveryAbsenceDisposition(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Internal ownership primitive. The coordinator supplies confirmed delivery
/// and policy capabilities and later consumes the exact membership receipt.
actor IOSAcceptedHistoryOutboxStore {
    nonisolated let capabilityOwnerIdentity:
        IOSAcceptedHistoryCapabilityOwnerIdentity
    nonisolated let deliveryStoreIdentity:
        IOSAcceptedOutputDeliveryStoreIdentity
    nonisolated let storeIdentity: IOSAcceptedHistoryOutboxStoreIdentity
    private nonisolated let operationGateBinding:
        IOSPersistenceOperationGateBinding
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
        case terminalProcessedRetirement(
            IOSAcceptedHistoryOutboxReceipt,
            IOSAcceptedOutputDeliveryAuthorization
        )
        case invalidatedRetirement(
            IOSAcceptedHistoryOutboxReceipt,
            IOSHistoryPolicyReceipt
        )
        case expiredRetirement(IOSAcceptedHistoryOutboxTemporalReceipt)

        var entry: IOSAcceptedHistoryOutboxEntry {
            switch self {
            case .transfer(let candidate): candidate.entry
            case .deliveryConfirmation(let candidate): candidate.entry
            case .observationConfirmation(let observation):
                observation.entry
            case .processedRetirement(let membership, _),
                 .terminalProcessedRetirement(let membership, _),
                 .invalidatedRetirement(let membership, _):
                membership.entry
            case .expiredRetirement(let classification):
                classification.membership.entry
            }
        }

        var receiptOrigin: IOSAcceptedHistoryOutboxReceiptOrigin {
            switch self {
            case .transfer(let candidate),
                 .deliveryConfirmation(let candidate):
                .delivery(candidate.delivery)
            case .observationConfirmation(let observation):
                .observation(observation)
            case .processedRetirement, .terminalProcessedRetirement,
                 .invalidatedRetirement,
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
            case .processedRetirement, .terminalProcessedRetirement,
                 .invalidatedRetirement,
                 .expiredRetirement:
                true
            }
        }

        var retirementMembership: IOSAcceptedHistoryOutboxReceipt {
            switch self {
            case .processedRetirement(let membership, _),
                 .terminalProcessedRetirement(let membership, _),
                 .invalidatedRetirement(let membership, _):
                membership
            case .expiredRetirement(let classification):
                classification.membership
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

    private struct UncertainDeliveryAbsenceIntent: Equatable, Sendable {
        let authorization: IOSAcceptedOutputDeliveryAuthorization
        let source: IOSAcceptedHistoryOutboxJournalSnapshot
    }

    private let journal: any IOSAcceptedHistoryOutboxJournalStoring
    private let now: @Sendable () -> Date
    private var uncertainIntent: UncertainIntent?
    private var uncertainDeliveryAbsenceIntent:
        UncertainDeliveryAbsenceIntent?

    init(
        applicationSupportDirectoryURL: URL,
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity =
            IOSAcceptedOutputDeliveryStoreIdentity(),
        storeIdentity: IOSAcceptedHistoryOutboxStoreIdentity =
            IOSAcceptedHistoryOutboxStoreIdentity(),
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity(),
        operationGateIdentity: IOSPersistenceOperationGateIdentity? = nil
    ) {
        journal = FoundationIOSAcceptedHistoryOutboxJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        now = { Date() }
        self.deliveryStoreIdentity = deliveryStoreIdentity
        self.storeIdentity = storeIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGateIdentity
        )
    }

    init(
        journal: any IOSAcceptedHistoryOutboxJournalStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        deliveryStoreIdentity: IOSAcceptedOutputDeliveryStoreIdentity =
            IOSAcceptedOutputDeliveryStoreIdentity(),
        storeIdentity: IOSAcceptedHistoryOutboxStoreIdentity =
            IOSAcceptedHistoryOutboxStoreIdentity(),
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity(),
        operationGateIdentity: IOSPersistenceOperationGateIdentity? = nil
    ) {
        self.journal = journal
        self.now = now
        self.deliveryStoreIdentity = deliveryStoreIdentity
        self.storeIdentity = storeIdentity
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        operationGateBinding = IOSPersistenceOperationGateBinding(
            identity: operationGateIdentity
        )
    }

    nonisolated func bindOperationGateIdentity(
        _ identity: IOSPersistenceOperationGateIdentity
    ) -> Bool {
        operationGateBinding.bind(identity)
    }

    func load() throws -> IOSAcceptedHistoryOutboxEnvelope? {
        try requireNoUncertainDeliveryAbsence()
        guard uncertainIntent?.operation.isRetirement != true else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        return try journal.load()?.envelope
    }

    func proveGuardedBaseline()
        throws -> IOSAcceptedHistoryOutboxGuardedBaselineEvidence {
        try requireNoUncertainDeliveryAbsence()
        guard uncertainIntent == nil else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        guard try journal.load()?.envelope.entries.isEmpty != false else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        return IOSAcceptedHistoryOutboxGuardedBaselineEvidence(
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    }

    func observeHead() throws -> IOSAcceptedHistoryOutboxObservation? {
        try requireNoUncertainDeliveryAbsence()
        guard uncertainIntent == nil else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        guard let snapshot = try journal.load(),
              let head = snapshot.envelope.entries.first else { return nil }
        return IOSAcceptedHistoryOutboxObservation(
            entry: head,
            snapshot: snapshot,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    }

    /// Compatibility wrapper. New work must consume only the store-selected
    /// FIFO head rather than selecting an arbitrary entry from a snapshot.
    func observe() throws -> [IOSAcceptedHistoryOutboxObservation]? {
        guard let head = try observeHead() else { return nil }
        return [head]
    }

    func classifyTemporalState(
        membership: IOSAcceptedHistoryOutboxReceipt
    ) throws -> IOSAcceptedHistoryOutboxTemporalReceipt {
        guard membership.storeIdentity == storeIdentity,
              membership.deliveryStoreIdentity == deliveryStoreIdentity,
              membership.capabilityOwnerIdentity
                == capabilityOwnerIdentity else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        try requireNoUncertainDeliveryAbsence()
        guard uncertainIntent == nil else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        guard let current = try journal.load() else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        let head = try requireRetirementMembership(
            membership,
            current: current
        )
        let temporalState = head.temporalState(at: try currentTime())
        return IOSAcceptedHistoryOutboxTemporalReceipt(
            temporalState: temporalState,
            membership: membership,
            head: head,
            snapshot: current,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    }

    func classifyDeliveryAbsence(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSAcceptedHistoryOutboxDeliveryAbsenceDisposition {
        guard operationGateBinding.proves(operationLeaseAuthorization) else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        guard authorization.storeIdentity == deliveryStoreIdentity,
              authorization.capabilityOwnerIdentity
                == capabilityOwnerIdentity else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        guard let marker = authorization.record.historyWrite,
              marker.state == .committed || marker.state == .cancelled,
              authorization.record.deliveryState != .discarded else {
            throw IOSAcceptedHistoryOutboxError.invalidTransition
        }
        guard uncertainIntent == nil else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        if let intent = uncertainDeliveryAbsenceIntent,
           intent.authorization != authorization {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }

        let current = try journal.load()
        if let intent = uncertainDeliveryAbsenceIntent {
            guard let current,
                  current.envelope == intent.source.envelope else {
                uncertainDeliveryAbsenceIntent = nil
                throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
            }
            return try publishDeliveryAbsence(
                authorization: authorization,
                source: current,
                operationLeaseAuthorization: operationLeaseAuthorization
            )
        }

        guard let current else {
            return .absent(
                deliveryAbsenceAuthorization(
                    for: authorization,
                    observedSnapshot: nil,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
            )
        }

        for entry in current.envelope.entries {
            switch entry.deliveryRelation(to: authorization) {
            case .unrelated:
                continue
            case .collision:
                return .collision
            case .pending, .committed, .cancelled, .discarded:
                return .matching
            }
        }
        return try publishDeliveryAbsence(
            authorization: authorization,
            source: current,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func transfer(
        reservation: IOSAcceptedOutputPendingHistoryTransferReservation
    ) throws -> IOSAcceptedHistoryOutboxReceipt {
        let delivery = reservation.deliveryAuthorization
        guard delivery.storeIdentity == deliveryStoreIdentity,
              delivery.capabilityOwnerIdentity == capabilityOwnerIdentity else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        try requireNoUncertainDeliveryAbsence()
        let claim = reservation.claimForOutbox(
            authorization: delivery,
            policyGeneration: reservation.confirmedPolicyGeneration,
            ownerIdentity: capabilityOwnerIdentity,
            deliveryStoreIdentity: deliveryStoreIdentity,
            outboxStoreIdentity: storeIdentity
        )
        switch claim {
        case .claimed, .claimedExpired:
            break
        case .expired:
            throw IOSAcceptedHistoryOutboxError.expired
        case .invalid:
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        guard uncertainIntent?.operation.isRetirement != true else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        let candidate = try IOSAcceptedHistoryOutboxCandidate(
            delivery: delivery
        )
        guard candidate.entry.policyGeneration
                == reservation.confirmedPolicyGeneration else {
            throw IOSAcceptedHistoryOutboxError.stalePolicyGeneration
        }
        let current = try journal.load()

        if let uncertainIntent {
            return try reconcileTransfer(
                uncertainIntent,
                candidate: candidate,
                current: current,
                monotonicExpired: claim == .claimedExpired
            )
        }

        if claim == .claimedExpired {
            guard let current,
                  (try? exactMembership(
                      of: candidate,
                      in: current.envelope
                  )) != nil else {
                throw IOSAcceptedHistoryOutboxError.expired
            }
            return try publish(
                Outcome(envelope: current.envelope),
                source: .existing(current),
                operation: .transfer(candidate)
            )
        }

        let temporalSnapshot = try currentTime()
        try requireLive(candidate.entry, at: temporalSnapshot)

        if let current {
            let outcome = try outcome(
                candidate,
                from: current.envelope,
                policyGeneration: reservation.confirmedPolicyGeneration,
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
                    policyGeneration: reservation.confirmedPolicyGeneration,
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
        guard delivery.storeIdentity == deliveryStoreIdentity,
              delivery.capabilityOwnerIdentity == capabilityOwnerIdentity else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        try requireNoUncertainDeliveryAbsence()
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
        guard observation.capabilityOwnerIdentity
                == capabilityOwnerIdentity,
              observation.storeIdentity == storeIdentity,
              observation.isHead else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        try requireNoUncertainDeliveryAbsence()
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
            case .processedRetirement, .terminalProcessedRetirement,
                 .invalidatedRetirement,
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
              current == observation.snapshot,
              current.envelope.entries.first?.hasSameImmutableBytes(
                  as: observation.entry
              ) == true else {
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
        guard membership.capabilityOwnerIdentity == capabilityOwnerIdentity,
              membership.deliveryStoreIdentity == deliveryStoreIdentity,
              decision.capabilityOwnerIdentity
                == capabilityOwnerIdentity else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        try retire(
            operation: .processedRetirement(membership, decision)
        )
    }

    func retireProcessed(
        membership: IOSAcceptedHistoryOutboxReceipt,
        terminalDelivery: IOSAcceptedOutputDeliveryAuthorization
    ) throws {
        guard membership.capabilityOwnerIdentity == capabilityOwnerIdentity,
              membership.deliveryStoreIdentity == deliveryStoreIdentity,
              terminalDelivery.storeIdentity == deliveryStoreIdentity,
              terminalDelivery.capabilityOwnerIdentity
                == capabilityOwnerIdentity else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        try retire(
            operation: .terminalProcessedRetirement(
                membership,
                terminalDelivery
            )
        )
    }

    func retireInvalidated(
        membership: IOSAcceptedHistoryOutboxReceipt,
        policy: IOSHistoryPolicyReceipt
    ) throws {
        guard membership.capabilityOwnerIdentity == capabilityOwnerIdentity,
              membership.deliveryStoreIdentity == deliveryStoreIdentity,
              policy.capabilityOwnerIdentity == capabilityOwnerIdentity else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        try retire(
            operation: .invalidatedRetirement(membership, policy)
        )
    }

    func retireExpired(
        membership: IOSAcceptedHistoryOutboxReceipt
    ) throws {
        guard membership.capabilityOwnerIdentity
                == capabilityOwnerIdentity,
              membership.deliveryStoreIdentity == deliveryStoreIdentity else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        if let uncertainIntent,
           case .expiredRetirement(let classification)
                = uncertainIntent.operation {
            guard classification.membership == membership else {
                throw IOSAcceptedHistoryOutboxError.commitUncertain
            }
            return try retireExpired(classification: classification)
        }
        try retireExpired(
            classification: classifyTemporalState(membership: membership)
        )
    }

    func retireExpired(
        classification: IOSAcceptedHistoryOutboxTemporalReceipt
    ) throws {
        guard classification.membership.deliveryStoreIdentity
                == deliveryStoreIdentity,
              classification.provesClassification(
            for: classification.membership,
            storeIdentity: storeIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity
        ) else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        try retire(operation: .expiredRetirement(classification))
    }

    @discardableResult
    func performStagingMaintenance()
        throws -> IOSAcceptedHistoryOutboxMaintenanceReport {
        try requireNoUncertainDeliveryAbsence()
        guard uncertainIntent?.operation.isRetirement != true else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
        return IOSAcceptedHistoryOutboxMaintenanceReport(
            try journal.performStagingMaintenance(now: now())
        )
    }
}

private extension IOSAcceptedHistoryOutboxStore {
    private func requireNoUncertainDeliveryAbsence() throws {
        guard uncertainDeliveryAbsenceIntent == nil else {
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        }
    }

    private func deliveryAbsenceAuthorization(
        for authorization: IOSAcceptedOutputDeliveryAuthorization,
        observedSnapshot: IOSAcceptedHistoryOutboxJournalSnapshot?,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) -> IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization {
        IOSAcceptedHistoryOutboxDeliveryAbsenceAuthorization(
            authorization: authorization,
            observedOutboxSnapshot: observedSnapshot,
            outboxStoreIdentity: storeIdentity,
            deliveryStoreIdentity: deliveryStoreIdentity,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    private func publishDeliveryAbsence(
        authorization: IOSAcceptedOutputDeliveryAuthorization,
        source: IOSAcceptedHistoryOutboxJournalSnapshot,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) throws -> IOSAcceptedHistoryOutboxDeliveryAbsenceDisposition {
        guard operationGateBinding.proves(operationLeaseAuthorization) else {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
        let intent = UncertainDeliveryAbsenceIntent(
            authorization: authorization,
            source: source
        )
        uncertainDeliveryAbsenceIntent = nil
        do {
            let confirmed = try journal.replace(
                source.envelope,
                expected: source,
                authorization:
                    IOSAcceptedHistoryOutboxJournalMutationAuthorization()
            )
            return .absent(
                deliveryAbsenceAuthorization(
                    for: authorization,
                    observedSnapshot: confirmed,
                    operationLeaseAuthorization:
                        operationLeaseAuthorization
                )
            )
        } catch IOSAcceptedHistoryOutboxError.commitUncertain {
            uncertainDeliveryAbsenceIntent = intent
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        } catch IOSAcceptedHistoryOutboxError.compareAndSwapFailed {
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
    }

    private func retire(operation: Operation) throws {
        precondition(operation.isRetirement)
        try requireNoUncertainDeliveryAbsence()
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
        guard membership.storeIdentity == storeIdentity,
              membership.deliveryStoreIdentity == deliveryStoreIdentity,
              membership.capabilityOwnerIdentity
                == capabilityOwnerIdentity,
              current == membership.snapshot,
              let confirmed = membership
                .confirmedEntryForAcceptedDecision(),
              current.envelope.entries.first?.hasSameImmutableBytes(
                  as: confirmed
              ) == true,
              membership.provesHeadMembership() else {
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
        case .terminalProcessedRetirement(
            let membership,
            let terminalDelivery
        ):
            guard membership.deliveryRelation(to: terminalDelivery)
                    == .committed else {
                throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
            }
        case .invalidatedRetirement(_, let policy):
            guard policy.state.policyGeneration > entry.policyGeneration else {
                throw IOSAcceptedHistoryOutboxError.stalePolicyGeneration
            }
        case .expiredRetirement(let classification):
            guard classification.provesClassification(
                for: operation.retirementMembership,
                storeIdentity: storeIdentity,
                capabilityOwnerIdentity: capabilityOwnerIdentity
            ) else {
                throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
            }
            switch classification.temporalState {
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
        } catch IOSAcceptedHistoryOutboxError.compareAndSwapFailed {
            guard uncertainIntent == nil else {
                throw IOSAcceptedHistoryOutboxError.commitUncertain
            }
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
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
                snapshot: snapshot,
                storeIdentity: storeIdentity,
                deliveryStoreIdentity: deliveryStoreIdentity,
                capabilityOwnerIdentity: capabilityOwnerIdentity
            )
        } catch IOSAcceptedHistoryOutboxError.commitUncertain {
            uncertainIntent = intent
            throw IOSAcceptedHistoryOutboxError.commitUncertain
        } catch IOSAcceptedHistoryOutboxError.compareAndSwapFailed {
            guard uncertainIntent == nil else {
                throw IOSAcceptedHistoryOutboxError.commitUncertain
            }
            throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
        }
    }

    private func reconcileTransfer(
        _ intent: UncertainIntent,
        candidate: IOSAcceptedHistoryOutboxCandidate,
        current: IOSAcceptedHistoryOutboxJournalSnapshot?,
        monotonicExpired: Bool
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

        if monotonicExpired {
            uncertainIntent = nil
            throw IOSAcceptedHistoryOutboxError.expired
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
