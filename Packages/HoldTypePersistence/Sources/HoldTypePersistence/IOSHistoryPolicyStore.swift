import Foundation

struct IOSHistoryPolicyReceipt: Equatable, Sendable {
    fileprivate let snapshot: IOSHistoryPolicyJournalSnapshot

    fileprivate init(snapshot: IOSHistoryPolicyJournalSnapshot) {
        self.snapshot = snapshot
    }

    var state: IOSHistoryPolicyState { snapshot.state }
}

extension IOSHistoryPolicyReceipt: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { "IOSHistoryPolicyReceipt(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// App-private raw policy owner. Production authority is issued only by the
/// accepted-History coordinator that proves baseline eligibility first.
actor IOSHistoryPolicyStore {
    private enum Source: Equatable {
        case missing
        case existing(IOSHistoryPolicyJournalSnapshot)
    }

    private enum Operation: Equatable {
        case establishBaseline
        case mutation(Mutation)
    }

    private enum Mutation: Equatable {
        case clear
        case setEnabled(Bool)
    }

    private struct UncertainIntent: Equatable {
        let source: Source
        let operation: Operation
        let intended: IOSHistoryPolicyState
    }

    private let journal: any IOSHistoryPolicyJournalStoring
    private let now: @Sendable () -> Date
    private var uncertainIntent: UncertainIntent?

    init(applicationSupportDirectoryURL: URL) {
        journal = FoundationIOSHistoryPolicyJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        now = { Date() }
    }

    init(
        journal: any IOSHistoryPolicyJournalStoring,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.now = now
    }

    /// A missing file stays missing. This read never creates policy authority.
    func load() throws -> IOSHistoryPolicyState? {
        try journal.load()?.state
    }

    /// Establishes the physical 1/1 policy only after the coordinator has
    /// sealed one joint observation proving that every legacy owner is empty.
    func establishAndConfirmBaseline(
        authorization: IOSHistoryPolicyBaselineAuthorization
    ) throws -> IOSHistoryPolicyReceipt {
        _ = authorization
        let current = try journal.load()

        if let uncertainIntent {
            guard uncertainIntent.operation == .establishBaseline else {
                throw IOSHistoryPolicyError.commitUncertain
            }
            return try reconcileBaseline(
                uncertainIntent,
                authorization: authorization,
                current: current
            )
        }

        if let current {
            guard current.state == .baseline else {
                throw IOSHistoryPolicyError.compareAndSwapFailed
            }
            return try replace(
                .baseline,
                expected: current,
                recording: UncertainIntent(
                    source: .existing(current),
                    operation: .establishBaseline,
                    intended: .baseline
                )
            )
        }

        let intent = UncertainIntent(
            source: .missing,
            operation: .establishBaseline,
            intended: .baseline
        )
        do {
            return try createBaseline(
                authorization: authorization,
                recording: intent
            )
        } catch IOSHistoryPolicyError.slotOccupied {
            guard let raced = try journal.load(),
                  raced.state == .baseline else {
                throw IOSHistoryPolicyError.compareAndSwapFailed
            }
            return try replace(
                .baseline,
                expected: raced,
                recording: UncertainIntent(
                    source: .existing(raced),
                    operation: .establishBaseline,
                    intended: .baseline
                )
            )
        }
    }

    /// Reconstructs process-local authority after relaunch by rewriting the
    /// exact logical value and confirming the new physical file revision.
    func confirm(
        expected: IOSHistoryPolicyExpectation
    ) throws -> IOSHistoryPolicyReceipt {
        let current = try journal.load()

        if let uncertainIntent {
            guard case .mutation = uncertainIntent.operation,
                  let current else {
                throw IOSHistoryPolicyError.commitUncertain
            }
            guard expected.matches(uncertainIntent.intended),
                  current.state == uncertainIntent.intended else {
                throw IOSHistoryPolicyError.commitUncertain
            }
            return try replace(
                uncertainIntent.intended,
                expected: current,
                recording: uncertainIntent
            )
        }

        guard let current else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }

        guard expected.matches(current.state) else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
        let replacement = try journal.replace(
            current.state,
            expected: current
        )
        uncertainIntent = nil
        return IOSHistoryPolicyReceipt(snapshot: replacement)
    }

    func clear(
        using receipt: IOSHistoryPolicyReceipt
    ) throws -> IOSHistoryPolicyReceipt {
        try apply(.clear, using: receipt)
    }

    func setHistoryEnabled(
        _ enabled: Bool,
        using receipt: IOSHistoryPolicyReceipt
    ) throws -> IOSHistoryPolicyReceipt {
        try apply(.setEnabled(enabled), using: receipt)
    }

    @discardableResult
    func performStagingMaintenance()
        throws -> IOSHistoryPolicyMaintenanceReport {
        IOSHistoryPolicyMaintenanceReport(
            try journal.performStagingMaintenance(now: now())
        )
    }
}

private extension IOSHistoryPolicyStore {
    private func apply(
        _ mutation: Mutation,
        using receipt: IOSHistoryPolicyReceipt
    ) throws -> IOSHistoryPolicyReceipt {
        let current = try journal.load()

        if let uncertainIntent {
            guard case .mutation = uncertainIntent.operation,
                  let current else {
                throw IOSHistoryPolicyError.commitUncertain
            }
            return try reconcile(
                uncertainIntent,
                mutation: mutation,
                receipt: receipt,
                current: current
            )
        }

        guard let current else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }

        if case .setEnabled(let enabled) = mutation,
           receipt.state.historyEnabled == enabled {
            guard current == receipt.snapshot else {
                throw IOSHistoryPolicyError.compareAndSwapFailed
            }
            return receipt
        }

        let intended = try successor(
            of: receipt.state,
            applying: mutation
        )
        let intent = UncertainIntent(
            source: .existing(receipt.snapshot),
            operation: .mutation(mutation),
            intended: intended
        )

        if current == receipt.snapshot {
            return try replace(
                intended,
                expected: current,
                recording: intent
            )
        }

        throw IOSHistoryPolicyError.compareAndSwapFailed
    }

    private func reconcile(
        _ intent: UncertainIntent,
        mutation: Mutation,
        receipt: IOSHistoryPolicyReceipt,
        current: IOSHistoryPolicyJournalSnapshot
    ) throws -> IOSHistoryPolicyReceipt {
        guard intent.source == .existing(receipt.snapshot),
              intent.operation == .mutation(mutation),
              try successor(of: receipt.state, applying: mutation)
                == intent.intended else {
            throw IOSHistoryPolicyError.commitUncertain
        }

        if current == receipt.snapshot {
            return try replace(
                intent.intended,
                expected: current,
                recording: intent
            )
        }
        guard current.state == intent.intended else {
            uncertainIntent = nil
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
        return try replace(
            intent.intended,
            expected: current,
            recording: intent
        )
    }

    private func reconcileBaseline(
        _ intent: UncertainIntent,
        authorization: IOSHistoryPolicyBaselineAuthorization,
        current: IOSHistoryPolicyJournalSnapshot?
    ) throws -> IOSHistoryPolicyReceipt {
        guard intent.intended == .baseline else {
            throw IOSHistoryPolicyError.commitUncertain
        }

        switch (intent.source, current) {
        case (.missing, .none):
            do {
                return try createBaseline(
                    authorization: authorization,
                    recording: intent
                )
            } catch IOSHistoryPolicyError.slotOccupied {
                guard let raced = try journal.load(),
                      raced.state == .baseline else {
                    uncertainIntent = nil
                    throw IOSHistoryPolicyError.compareAndSwapFailed
                }
                return try replace(
                    .baseline,
                    expected: raced,
                    recording: UncertainIntent(
                        source: .existing(raced),
                        operation: .establishBaseline,
                        intended: .baseline
                    )
                )
            }
        case (_, .some(let current)) where current.state == .baseline:
            return try replace(
                .baseline,
                expected: current,
                recording: UncertainIntent(
                    source: .existing(current),
                    operation: .establishBaseline,
                    intended: .baseline
                )
            )
        default:
            uncertainIntent = nil
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
    }

    private func createBaseline(
        authorization: IOSHistoryPolicyBaselineAuthorization,
        recording intent: UncertainIntent
    ) throws -> IOSHistoryPolicyReceipt {
        do {
            let created = try journal.create(
                .baseline,
                authorization: authorization
            )
            uncertainIntent = nil
            return IOSHistoryPolicyReceipt(snapshot: created)
        } catch IOSHistoryPolicyError.commitUncertain {
            uncertainIntent = intent
            throw IOSHistoryPolicyError.commitUncertain
        }
    }

    private func replace(
        _ intended: IOSHistoryPolicyState,
        expected: IOSHistoryPolicyJournalSnapshot,
        recording intent: UncertainIntent
    ) throws -> IOSHistoryPolicyReceipt {
        do {
            let replacement = try journal.replace(
                intended,
                expected: expected
            )
            uncertainIntent = nil
            return IOSHistoryPolicyReceipt(snapshot: replacement)
        } catch IOSHistoryPolicyError.commitUncertain {
            uncertainIntent = intent
            throw IOSHistoryPolicyError.commitUncertain
        }
    }

    private func successor(
        of state: IOSHistoryPolicyState,
        applying mutation: Mutation
    ) throws -> IOSHistoryPolicyState {
        let nextRevision = state.revision.addingReportingOverflow(1)
        let nextGeneration = state.policyGeneration.addingReportingOverflow(1)
        guard !nextRevision.overflow,
              !nextGeneration.overflow else {
            throw IOSHistoryPolicyError.revisionOverflow
        }

        let enabled = switch mutation {
        case .clear:
            state.historyEnabled
        case .setEnabled(let enabled):
            enabled
        }
        return try IOSHistoryPolicyState(
            revision: nextRevision.partialValue,
            historyEnabled: enabled,
            policyGeneration: nextGeneration.partialValue
        )
    }
}
