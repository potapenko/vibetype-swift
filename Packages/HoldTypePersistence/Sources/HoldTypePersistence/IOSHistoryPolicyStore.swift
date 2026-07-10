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
    private enum Mutation: Equatable {
        case clear
        case setEnabled(Bool)
    }

    private struct UncertainIntent: Equatable {
        let source: IOSHistoryPolicyJournalSnapshot
        let mutation: Mutation
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

    /// Reconstructs process-local authority after relaunch by rewriting the
    /// exact logical value and confirming the new physical file revision.
    func confirm(
        expected: IOSHistoryPolicyExpectation
    ) throws -> IOSHistoryPolicyReceipt {
        guard let current = try journal.load() else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }

        if let uncertainIntent {
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
        guard let current = try journal.load() else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }

        if let uncertainIntent {
            return try reconcile(
                uncertainIntent,
                mutation: mutation,
                receipt: receipt,
                current: current
            )
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
            source: receipt.snapshot,
            mutation: mutation,
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
        guard intent.source == receipt.snapshot,
              intent.mutation == mutation,
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
