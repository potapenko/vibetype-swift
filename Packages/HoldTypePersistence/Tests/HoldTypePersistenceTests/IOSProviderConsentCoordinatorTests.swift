import Foundation
import Testing
@testable import HoldTypePersistence

struct IOSProviderConsentCoordinatorTests {
    @Test func absentAcceptanceMintsRevisionOneAndLiveStageAuthority() async throws {
        let epoch = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let journal = IOSProviderConsentJournalFake()
        let coordinator = makeCoordinator(journal: journal, epoch: epoch)
        let initial = await coordinator.observe()

        #expect(initial.status == .notReviewed)
        #expect(initial.decisionAt == nil)
        #expect(journal.createCallCount == 0)

        let accepted = try await coordinator.accept(
            using: initial,
            decisionAt: try fixtureDate("2026-07-12T10:00:00.111Z")
        )
        let record = try #require(journal.currentRecord)

        #expect(accepted.status == .acceptedCurrentDisclosure)
        #expect(record.epochID == epoch)
        #expect(record.revision == 1)
        #expect(record.disclosureVersion == 1)
        #expect(record.state == .accepted)
        #expect(journal.createCallCount == 1)

        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        for stage in IOSProviderConsentProviderStage.allCases {
            #expect(coordinator.validate(authorization, for: stage))
            #expect(
                coordinator.revalidateAfterProviderResponse(
                    authorization,
                    for: stage
                )
            )
        }
    }

    @Test func alreadyCurrentAcceptanceIsAnExactNoOp() async throws {
        let record = try fixtureRecord(state: .accepted, revision: 4)
        let journal = IOSProviderConsentJournalFake(record: record)
        let coordinator = makeCoordinator(journal: journal)
        let observed = await coordinator.observe()

        let saved = try await coordinator.accept(
            using: observed,
            decisionAt: try fixtureDate("2026-07-13T10:00:00.000Z")
        )

        #expect(saved == observed)
        #expect(journal.currentRecord == record)
        #expect(journal.replaceCallCount == 0)
    }

    @Test func withdrawalInvalidatesAuthorityAndFreshReacceptAdvancesSameEpoch() async throws {
        let record = try fixtureRecord(state: .accepted, revision: 1)
        let journal = IOSProviderConsentJournalFake(record: record)
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let oldAuthorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )

        let withdrawn = try await coordinator.withdraw(
            using: accepted,
            decisionAt: try fixtureDate("2026-07-12T10:01:00.000Z")
        )

        #expect(withdrawn.status == .withdrawn)
        #expect(!coordinator.validate(oldAuthorization, for: .transcription))
        #expect(coordinator.makeAuthorization(from: withdrawn) == nil)
        #expect(journal.currentRecord?.revision == 2)
        #expect(journal.currentRecord?.state == .withdrawn)

        await #expect(throws: IOSProviderConsentError.staleObservation) {
            _ = try await coordinator.accept(using: accepted)
        }

        let fresh = await coordinator.observe()
        let reaccepted = try await coordinator.accept(
            using: fresh,
            decisionAt: try fixtureDate("2026-07-12T10:02:00.000Z")
        )
        let reacceptedRecord = try #require(journal.currentRecord)

        #expect(reaccepted.status == .acceptedCurrentDisclosure)
        #expect(reacceptedRecord.epochID == record.epochID)
        #expect(reacceptedRecord.revision == 3)
        #expect(reacceptedRecord.state == .accepted)
    }

    @Test func alreadyWithdrawnDecisionIsAnExactNoOp() async throws {
        let record = try fixtureRecord(state: .withdrawn, revision: 9)
        let journal = IOSProviderConsentJournalFake(record: record)
        let coordinator = makeCoordinator(journal: journal)
        let observed = await coordinator.observe()

        let result = try await coordinator.withdraw(using: observed)

        #expect(result == observed)
        #expect(journal.currentRecord == record)
        #expect(journal.replaceCallCount == 0)
    }

    @Test func olderDisclosureRequiresReviewAndExplicitAcceptance() async throws {
        let old = try fixtureRecord(
            state: .accepted,
            revision: 2,
            disclosureVersion: 1
        )
        let journal = IOSProviderConsentJournalFake(record: old)
        let coordinator = IOSProviderConsentCoordinator(
            journal: journal,
            currentDisclosureVersion: 2,
            makeEpochID: { UUID() }
        )

        let observation = await coordinator.observe()
        #expect(observation.status == .reviewRequired)
        #expect(coordinator.makeAuthorization(from: observation) == nil)

        let accepted = try await coordinator.accept(
            using: observation,
            decisionAt: try fixtureDate("2026-07-12T11:00:00.000Z")
        )

        #expect(accepted.status == .acceptedCurrentDisclosure)
        #expect(journal.currentRecord?.epochID == old.epochID)
        #expect(journal.currentRecord?.revision == 3)
        #expect(journal.currentRecord?.disclosureVersion == 2)
    }

    @Test func unreadableDataCannotBeOverwrittenAndResetUsesExactRevision() async throws {
        let unreadable = IOSProviderConsentJournalSnapshot(
            content: .unreadable,
            testingRevision: 51
        )
        let journal = IOSProviderConsentJournalFake(snapshot: unreadable)
        let coordinator = makeCoordinator(journal: journal)
        let observation = await coordinator.observe()

        #expect(observation.status == .reviewRequired)
        #expect(observation.canResetUnreadableData)
        await #expect(
            throws: IOSProviderConsentError.unreadableDataRequiresReset
        ) {
            _ = try await coordinator.accept(using: observation)
        }

        let reset = try await coordinator.resetUnreadableConsentData(
            using: observation
        )

        #expect(reset.status == .notReviewed)
        #expect(journal.snapshot == nil)
        #expect(journal.removeCallCount == 1)

        await #expect(throws: IOSProviderConsentError.staleObservation) {
            _ = try await coordinator.resetUnreadableConsentData(
                using: observation
            )
        }
    }

    @Test func readableObservationCannotAuthorizeReset() async throws {
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord()
        )
        let coordinator = makeCoordinator(journal: journal)
        let observation = await coordinator.observe()

        await #expect(
            throws: IOSProviderConsentError.resetRequiresUnreadableObservation
        ) {
            _ = try await coordinator.resetUnreadableConsentData(
                using: observation
            )
        }
        #expect(journal.removeCallCount == 0)
    }

    @Test func stalePhysicalExpectationNeverWrites() async throws {
        let record = try fixtureRecord(state: .accepted, revision: 1)
        let journal = IOSProviderConsentJournalFake(record: record)
        let coordinator = makeCoordinator(journal: journal)
        let observation = await coordinator.observe()
        journal.installExternally(
            try fixtureRecord(
                state: .withdrawn,
                revision: 2,
                epochID: record.epochID
            )
        )

        await #expect(throws: IOSProviderConsentError.staleObservation) {
            _ = try await coordinator.withdraw(using: observation)
        }
        #expect(journal.replaceCallCount == 0)
    }

    @Test func revisionOverflowFailsClosedWithoutWrite() async throws {
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: Int64.max)
        )
        let coordinator = IOSProviderConsentCoordinator(
            journal: journal,
            currentDisclosureVersion: 2
        )
        let observation = await coordinator.observe()

        await #expect(throws: IOSProviderConsentError.revisionOverflow) {
            _ = try await coordinator.accept(using: observation)
        }
        #expect(journal.replaceCallCount == 0)
    }

    @Test func commitUncertainExactIntentRepeatsDirectoryBarrier() async throws {
        let journal = IOSProviderConsentJournalFake()
        journal.nextMutation = .commitIntendedThenFail(.commitUncertain)
        let coordinator = makeCoordinator(journal: journal)
        let observation = await coordinator.observe()

        let accepted = try await coordinator.accept(
            using: observation,
            decisionAt: try fixtureDate("2026-07-12T12:00:00.000Z")
        )

        #expect(accepted.status == .acceptedCurrentDisclosure)
        #expect(journal.synchronizeCallCount == 1)
        #expect(journal.loadCallCount >= 3)
    }

    @Test func commitUncertainPriorTruthIsNotGuessedAsSuccess() async throws {
        let journal = IOSProviderConsentJournalFake()
        journal.nextMutation = .failBeforeCommit(.commitUncertain)
        let coordinator = makeCoordinator(journal: journal)
        let observation = await coordinator.observe()

        await #expect(throws: IOSProviderConsentError.mutationNotSaved) {
            _ = try await coordinator.accept(using: observation)
        }

        #expect(journal.snapshot == nil)
        #expect(journal.synchronizeCallCount == 0)
    }

    @Test func commitUncertainDifferentResultStaysUnavailable() async throws {
        let other = try fixtureRecord(
            state: .withdrawn,
            revision: 1,
            epochID: UUID(uuidString: "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF")!
        )
        let journal = IOSProviderConsentJournalFake()
        journal.nextMutation = .commitAlternateThenFail(
            other,
            .commitUncertain
        )
        let coordinator = makeCoordinator(journal: journal)
        let observation = await coordinator.observe()

        await #expect(throws: IOSProviderConsentError.commitUncertain) {
            _ = try await coordinator.accept(using: observation)
        }
        #expect(journal.synchronizeCallCount == 0)
    }

    @Test func uncertainResetConfirmsAbsenceAcrossRepeatedBarrier() async throws {
        let unreadable = IOSProviderConsentJournalSnapshot(
            content: .unreadable,
            testingRevision: 72
        )
        let journal = IOSProviderConsentJournalFake(snapshot: unreadable)
        journal.nextMutation = .commitIntendedThenFail(.commitUncertain)
        let coordinator = makeCoordinator(journal: journal)
        let observation = await coordinator.observe()

        let reset = try await coordinator.resetUnreadableConsentData(
            using: observation
        )

        #expect(reset.status == .notReviewed)
        #expect(journal.synchronizeCallCount == 1)
        #expect(journal.snapshot == nil)
    }

    @Test func reconciliationBarrierFailureNeverMintsAuthority() async throws {
        let journal = IOSProviderConsentJournalFake()
        journal.nextMutation = .commitIntendedThenFail(.commitUncertain)
        journal.synchronizeError = .commitUncertain
        let coordinator = makeCoordinator(journal: journal)
        let observation = await coordinator.observe()

        await #expect(throws: IOSProviderConsentError.commitUncertain) {
            _ = try await coordinator.accept(using: observation)
        }

        let stillBlocked = await coordinator.observe()
        #expect(stillBlocked.status == .localDataUnavailable)
        #expect(coordinator.makeAuthorization(from: stillBlocked) == nil)

        journal.synchronizeError = nil
        let reconciled = await coordinator.observe()
        #expect(reconciled.status == .acceptedCurrentDisclosure)
        #expect(coordinator.makeAuthorization(from: reconciled) == nil)

        let explicitlyAccepted = try await coordinator.accept(using: reconciled)
        #expect(coordinator.makeAuthorization(from: explicitlyAccepted) != nil)
    }

    @Test func withdrawalClosesGateEvenWhenRepositoryMutationFails() async throws {
        let record = try fixtureRecord(state: .accepted, revision: 1)
        let journal = IOSProviderConsentJournalFake(record: record)
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )

        journal.nextMutation = .failBeforeCommit(.mutationNotSaved)
        await #expect(throws: IOSProviderConsentError.mutationNotSaved) {
            _ = try await coordinator.withdraw(
                using: accepted,
                decisionAt: try fixtureDate("2026-07-12T13:00:00.000Z")
            )
        }
        #expect(!coordinator.validate(authorization, for: .translation))
    }

    @Test func closedFenceRejectsLateAndPassiveAdoptionUntilExplicitAccept() {
        let gate = IOSProviderConsentAuthorizationGate()
        let binding = IOSProviderConsentAuthorizationBinding(
            ownerIdentity: IOSProviderConsentOwnerIdentity(),
            epochID: UUID(),
            revision: 3,
            disclosureVersion: 1
        )
        let originalFence = gate.currentFence()
        gate.adoptPassively(binding: binding, ifFenceIs: originalFence)
        let originalAuthorization = gate.makeAuthorization(for: binding)
        #expect(originalAuthorization != nil)

        gate.close()
        #expect(originalAuthorization.map(gate.validate) == false)

        gate.adoptAfterExplicitAcceptance(
            binding: binding,
            ifFenceIs: originalFence
        )
        #expect(gate.makeAuthorization(for: binding) == nil)

        let currentFence = gate.currentFence()
        gate.adoptPassively(binding: binding, ifFenceIs: currentFence)
        #expect(gate.makeAuthorization(for: binding) == nil)

        gate.adoptAfterExplicitAcceptance(
            binding: binding,
            ifFenceIs: currentFence
        )
        #expect(gate.makeAuthorization(for: binding) != nil)
    }

    @Test func observationsAreBoundToOneProcessOwner() async throws {
        let journal = IOSProviderConsentJournalFake()
        let first = makeCoordinator(journal: journal)
        let second = makeCoordinator(journal: journal)
        let foreign = await first.observe()

        await #expect(throws: IOSProviderConsentError.staleObservation) {
            _ = try await second.accept(using: foreign)
        }
        #expect(journal.createCallCount == 0)
    }

    @Test func unavailableLoadAndInvalidDisclosureFailClosed() async throws {
        let unavailableJournal = IOSProviderConsentJournalFake()
        unavailableJournal.loadError = .localDataUnavailable
        let unavailable = makeCoordinator(journal: unavailableJournal)
        let observation = await unavailable.observe()

        #expect(observation.status == .localDataUnavailable)
        #expect(coordinatorAuthorizationIsAbsent(unavailable, observation))
        await #expect(throws: IOSProviderConsentError.localDataUnavailable) {
            _ = try await unavailable.accept(using: observation)
        }

        let invalidJournal = IOSProviderConsentJournalFake()
        let invalid = IOSProviderConsentCoordinator(
            journal: invalidJournal,
            currentDisclosureVersion: 0
        )
        let invalidObservation = await invalid.observe()
        #expect(invalidObservation.status == .localDataUnavailable)
        await #expect(throws: IOSProviderConsentError.invalidDisclosureVersion) {
            _ = try await invalid.accept(using: invalidObservation)
        }
    }

    @Test func publicObservationsAuthorizationsAndCoordinatorAreRedacted() async throws {
        let canary = "PROVIDER-CONSENT-PRIVATE-CANARY"
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord()
        )
        let coordinator = makeCoordinator(journal: journal)
        let observation = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: observation)
        )
        let values: [Any] = [
            coordinator,
            observation,
            authorization,
            observation.source,
            try #require(journal.snapshot),
        ]

        for value in values {
            var rendered = canary
            dump(value, to: &rendered)
            #expect(!String(describing: value).contains(canary))
            #expect(!String(reflecting: value).contains(canary))
            #expect(rendered.filter { $0 == "\n" }.count <= 1)
        }
    }

    private func makeCoordinator(
        journal: IOSProviderConsentJournalFake,
        epoch: UUID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
    ) -> IOSProviderConsentCoordinator {
        IOSProviderConsentCoordinator(
            journal: journal,
            currentDisclosureVersion: 1,
            makeEpochID: { epoch }
        )
    }

    private func fixtureRecord(
        state: IOSProviderConsentDecisionState = .accepted,
        revision: Int64 = 1,
        disclosureVersion: Int64 = 1,
        epochID: UUID = UUID(
            uuidString: "01234567-89AB-4CDE-8123-456789ABCDEF"
        )!
    ) throws -> IOSProviderConsentRecord {
        IOSProviderConsentRecord(
            epochID: epochID,
            revision: revision,
            disclosureVersion: disclosureVersion,
            state: state,
            decisionAt: try fixtureDate("2026-07-12T09:00:00.000Z")
        )
    }

    private func fixtureDate(_ value: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return try #require(formatter.date(from: value))
    }

    private func coordinatorAuthorizationIsAbsent(
        _ coordinator: IOSProviderConsentCoordinator,
        _ observation: IOSProviderConsentObservation
    ) -> Bool {
        coordinator.makeAuthorization(from: observation) == nil
    }
}

private final class IOSProviderConsentJournalFake:
    IOSProviderConsentJournalStoring,
    @unchecked Sendable {
    enum Mutation {
        case succeed
        case failBeforeCommit(IOSProviderConsentJournalError)
        case commitIntendedThenFail(IOSProviderConsentJournalError)
        case commitAlternateThenFail(
            IOSProviderConsentRecord,
            IOSProviderConsentJournalError
        )
    }

    private let lock = NSLock()
    private var storedSnapshot: IOSProviderConsentJournalSnapshot?
    private var nextTestingRevision: UInt64 = 100
    private var storedLoadCallCount = 0
    private var storedCreateCallCount = 0
    private var storedReplaceCallCount = 0
    private var storedRemoveCallCount = 0
    private var storedSynchronizeCallCount = 0
    var loadError: IOSProviderConsentJournalError?
    var synchronizeError: IOSProviderConsentJournalError?
    var nextMutation: Mutation = .succeed

    var snapshot: IOSProviderConsentJournalSnapshot? {
        lock.withLock { storedSnapshot }
    }

    var currentRecord: IOSProviderConsentRecord? {
        lock.withLock {
            guard case .readable(let record)? = storedSnapshot?.content else {
                return nil
            }
            return record
        }
    }

    var loadCallCount: Int { lock.withLock { storedLoadCallCount } }
    var createCallCount: Int { lock.withLock { storedCreateCallCount } }
    var replaceCallCount: Int { lock.withLock { storedReplaceCallCount } }
    var removeCallCount: Int { lock.withLock { storedRemoveCallCount } }
    var synchronizeCallCount: Int {
        lock.withLock { storedSynchronizeCallCount }
    }

    init(
        record: IOSProviderConsentRecord? = nil,
        snapshot: IOSProviderConsentJournalSnapshot? = nil
    ) {
        if let snapshot {
            storedSnapshot = snapshot
        } else if let record {
            storedSnapshot = IOSProviderConsentJournalSnapshot(
                content: .readable(record),
                testingRevision: 1
            )
        }
    }

    func load() throws -> IOSProviderConsentJournalSnapshot? {
        try lock.withLock {
            storedLoadCallCount += 1
            if let loadError { throw loadError }
            return storedSnapshot
        }
    }

    func create(_ record: IOSProviderConsentRecord) throws
        -> IOSProviderConsentJournalSnapshot {
        try lock.withLock {
            storedCreateCallCount += 1
            guard storedSnapshot == nil else {
                throw IOSProviderConsentJournalError.staleRevision
            }
            return try applyMutation(intended: record)
        }
    }

    func replace(
        _ record: IOSProviderConsentRecord,
        expected: IOSProviderConsentJournalSnapshot
    ) throws -> IOSProviderConsentJournalSnapshot {
        return try lock.withLock {
            storedReplaceCallCount += 1
            guard storedSnapshot == expected else {
                throw IOSProviderConsentJournalError.staleRevision
            }
            return try applyMutation(intended: record)
        }
    }

    func removeUnreadable(
        expected: IOSProviderConsentJournalSnapshot
    ) throws {
        try lock.withLock {
            storedRemoveCallCount += 1
            guard storedSnapshot == expected,
                  expected.content == .unreadable else {
                throw IOSProviderConsentJournalError.staleRevision
            }
            let mutation = consumeMutation()
            switch mutation {
            case .succeed:
                storedSnapshot = nil
            case .failBeforeCommit(let error):
                throw error
            case .commitIntendedThenFail(let error),
                    .commitAlternateThenFail(_, let error):
                storedSnapshot = nil
                throw error
            }
        }
    }

    func synchronizeDirectory() throws {
        try lock.withLock {
            storedSynchronizeCallCount += 1
            if let synchronizeError { throw synchronizeError }
        }
    }

    func installExternally(_ record: IOSProviderConsentRecord) {
        lock.withLock {
            storedSnapshot = mintSnapshot(record)
        }
    }

    private func applyMutation(
        intended: IOSProviderConsentRecord
    ) throws -> IOSProviderConsentJournalSnapshot {
        let mutation = consumeMutation()
        switch mutation {
        case .succeed:
            let snapshot = mintSnapshot(intended)
            storedSnapshot = snapshot
            return snapshot
        case .failBeforeCommit(let error):
            throw error
        case .commitIntendedThenFail(let error):
            storedSnapshot = mintSnapshot(intended)
            throw error
        case .commitAlternateThenFail(let record, let error):
            storedSnapshot = mintSnapshot(record)
            throw error
        }
    }

    private func consumeMutation() -> Mutation {
        defer { nextMutation = .succeed }
        return nextMutation
    }

    private func mintSnapshot(
        _ record: IOSProviderConsentRecord
    ) -> IOSProviderConsentJournalSnapshot {
        defer { nextTestingRevision += 1 }
        return IOSProviderConsentJournalSnapshot(
            content: .readable(record),
            testingRevision: nextTestingRevision
        )
    }
}
