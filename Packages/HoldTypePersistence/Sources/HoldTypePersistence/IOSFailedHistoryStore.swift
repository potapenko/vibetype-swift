import Foundation

struct IOSFailedHistoryJournalMutationAuthorization: Sendable {
    fileprivate init() {}

    #if DEBUG
    init(testingToken: Void) {
        _ = testingToken
        self.init()
    }
    #endif
}

struct IOSFailedHistoryGuardedBaselineEvidence: Sendable {
    let capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity

    fileprivate init(
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) {
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }
}

extension IOSFailedHistoryGuardedBaselineEvidence:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryGuardedBaselineEvidence(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// Internal raw repository. App-facing reads are added only with policy
/// filtering and audio-availability projection in the integration checkpoint.
actor IOSFailedHistoryStore {
    nonisolated let capabilityOwnerIdentity:
        IOSAcceptedHistoryCapabilityOwnerIdentity
    private let journal: any IOSFailedHistoryJournalStoring
    private let now: @Sendable () -> Date

    init(
        applicationSupportDirectoryURL: URL,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
    ) {
        journal = FoundationIOSFailedHistoryJournalRepository(
            applicationSupportDirectoryURL: applicationSupportDirectoryURL
        )
        now = { Date() }
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
    }

    init(
        journal: any IOSFailedHistoryJournalStoring,
        capabilityOwnerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.journal = journal
        self.capabilityOwnerIdentity = capabilityOwnerIdentity
        self.now = now
    }

    /// Raw state is coordinator-only because old policy generations and audio
    /// cleanup tombstones intentionally survive until bounded reconciliation.
    func load() throws -> IOSFailedHistoryEnvelope? {
        try journal.load()?.envelope
    }

    func proveGuardedBaseline()
        throws -> IOSFailedHistoryGuardedBaselineEvidence {
        if let envelope = try journal.load()?.envelope {
            guard envelope.entries.isEmpty,
                  envelope.audioCleanup.isEmpty else {
                throw IOSFailedHistoryError.compareAndSwapFailed
            }
        }
        return IOSFailedHistoryGuardedBaselineEvidence(
            capabilityOwnerIdentity: capabilityOwnerIdentity
        )
    }

    @discardableResult
    func performStagingMaintenance()
        throws -> IOSFailedHistoryMaintenanceReport {
        IOSFailedHistoryMaintenanceReport(
            try journal.performStagingMaintenance(now: now())
        )
    }
}
