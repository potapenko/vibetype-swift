import Darwin
import Foundation
import Testing
@testable import HoldTypePersistence

struct IOSProviderConsentCoordinatorTests {
    @Test func publicCoordinatorUsesCanonicalApplicationSupportConstruction() {
        let expected = URL.applicationSupportDirectory

        #expect(
            IOSProviderConsentCoordinator
                .canonicalApplicationSupportDirectoryURL == expected
        )
        let coordinator = IOSProviderConsentCoordinator()
        #expect(String(describing: coordinator).contains("redacted"))
    }

    @Test func canonicalBootstrapCreatesMissingOwnerOnlyRootBeforePinning()
        async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "provider-consent-bootstrap-\(UUID().uuidString)",
                isDirectory: true
            )
        let library = parent.appendingPathComponent(
            "Library",
            isDirectory: true
        )
        let support = library.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: library.path
        )
        #expect(!FileManager.default.fileExists(atPath: support.path))

        let bootstrapIdentity = try #require(
            IOSProviderConsentCoordinator
                .bootstrapApplicationSupportDirectory(at: support)
        )
        var status = stat()
        #expect(Darwin.lstat(support.path, &status) == 0)
        #expect(status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR))
        #expect(status.st_uid == Darwin.geteuid())
        #expect(status.st_mode & mode_t(0o7777) == mode_t(0o700))
        #expect(
            bootstrapIdentity == IOSPersistenceRepositoryRootIdentity(
                device: status.st_dev,
                inode: status.st_ino
            )
        )

        let coordinator = IOSProviderConsentCoordinator(
            applicationSupportDirectoryURL: support,
            registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        )
        let initial = await coordinator.observe()
        #expect(initial.status == .notReviewed)
        let accepted = try await coordinator.accept(using: initial)
        #expect(accepted.status == .acceptedCurrentDisclosure)
        #expect(coordinator.makeAuthorization(from: accepted) != nil)
    }

    @Test func canonicalBootstrapRejectsPhysicalRootSwapBeforeRegistryPin()
        async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "provider-consent-bootstrap-swap-\(UUID().uuidString)",
                isDirectory: true
            )
        let library = parent.appendingPathComponent(
            "Library",
            isDirectory: true
        )
        let support = library.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        let original = library.appendingPathComponent(
            "Original Application Support",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: library.path
        )
        let handoffFailures = LockedCounter()

        let coordinator = IOSProviderConsentCoordinator(
            bootstrappingApplicationSupportDirectoryURL: support,
            registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry(),
            beforeRegistryPin: {
                do {
                    try FileManager.default.moveItem(
                        at: support,
                        to: original
                    )
                    try FileManager.default.createDirectory(
                        at: support,
                        withIntermediateDirectories: false
                    )
                    try FileManager.default.setAttributes(
                        [.posixPermissions: NSNumber(value: 0o700)],
                        ofItemAtPath: support.path
                    )
                } catch {
                    handoffFailures.increment()
                }
            }
        )

        #expect(handoffFailures.value == 0)
        let observation = await coordinator.observe()
        #expect(observation.status == .localDataUnavailable)
        #expect(coordinator.makeAuthorization(from: observation) == nil)
        await #expect(throws: IOSProviderConsentError.localDataUnavailable) {
            _ = try await coordinator.accept(using: observation)
        }
    }

    @Test func canonicalBootstrapRejectsSymlinkHandoffBeforeRegistryPin()
        async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "provider-consent-bootstrap-link-\(UUID().uuidString)",
                isDirectory: true
            )
        let library = parent.appendingPathComponent(
            "Library",
            isDirectory: true
        )
        let support = library.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        let original = library.appendingPathComponent(
            "Original Application Support",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: library.path
        )
        let handoffFailures = LockedCounter()

        let coordinator = IOSProviderConsentCoordinator(
            bootstrappingApplicationSupportDirectoryURL: support,
            registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry(),
            beforeRegistryPin: {
                do {
                    try FileManager.default.moveItem(
                        at: support,
                        to: original
                    )
                    try FileManager.default.createSymbolicLink(
                        at: support,
                        withDestinationURL: original
                    )
                } catch {
                    handoffFailures.increment()
                }
            }
        )

        #expect(handoffFailures.value == 0)
        let observation = await coordinator.observe()
        #expect(observation.status == .localDataUnavailable)
        #expect(coordinator.makeAuthorization(from: observation) == nil)
    }

    @Test func canonicalBootstrapRevalidatesParentModeBeforeAuthority()
        async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "provider-consent-bootstrap-parent-\(UUID().uuidString)",
                isDirectory: true
            )
        let library = parent.appendingPathComponent(
            "Library",
            isDirectory: true
        )
        let support = library.appendingPathComponent(
            "Application Support",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: library.path
        )
        let handoffFailures = LockedCounter()

        let coordinator = IOSProviderConsentCoordinator(
            bootstrappingApplicationSupportDirectoryURL: support,
            registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry(),
            beforeRegistryPin: {
                do {
                    try FileManager.default.setAttributes(
                        [.posixPermissions: NSNumber(value: 0o777)],
                        ofItemAtPath: library.path
                    )
                } catch {
                    handoffFailures.increment()
                }
            }
        )

        #expect(handoffFailures.value == 0)
        let observation = await coordinator.observe()
        #expect(observation.status == .localDataUnavailable)
        #expect(coordinator.makeAuthorization(from: observation) == nil)
    }

    @Test func productionCoordinatorsShareOneOwnerAndAuthorizationGate()
        async throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: support) }
        try FileManager.default.createDirectory(
            at: support,
            withIntermediateDirectories: true
        )
        let first = IOSProviderConsentCoordinator(
            applicationSupportDirectoryURL: support
        )
        let second = IOSProviderConsentCoordinator(
            applicationSupportDirectoryURL: support
        )

        let accepted = try await first.accept(
            using: first.observe(),
            decisionAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let secondObservation = await second.observe()
        let authorization = try #require(
            second.makeAuthorization(from: secondObservation)
        )
        let cancelled = LockedCounter()
        let onCancellation: @Sendable () -> Void = { cancelled.increment() }
        let registrationCandidate = await second.registerProviderDispatch(
            authorization,
            for: .transcription,
            onCancellation: onCancellation
        )
        let registration = try #require(registrationCandidate)
        let launch: @Sendable () -> Void = {}
        let didLaunch = await second.launchProviderDispatch(
            registration,
            launch: launch
        )
        #expect(didLaunch)

        _ = try await first.withdraw(
            using: accepted,
            decisionAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
        #expect(cancelled.value == 1)
        let onResultCancellation: @Sendable () -> Void = {}
        let lateResult = await second.finishProviderDispatch(
            registration,
            onResultCancellation: onResultCancellation
        )
        #expect(lateResult == nil)
        let lateRegistration = await second.registerProviderDispatch(
            authorization,
            for: .translation,
            onCancellation: onCancellation
        )
        #expect(lateRegistration == nil)
    }

    @Test func physicalRootReplacementCancelsDispatchAndResultCapabilities()
        async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "provider-consent-root-\(UUID().uuidString)",
                isDirectory: true
            )
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let original = parent.appendingPathComponent(
            "original",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let coordinator = IOSProviderConsentCoordinator(
            applicationSupportDirectoryURL: root,
            registry: IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        )
        let accepted = try await coordinator.accept(
            using: coordinator.observe()
        )
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let dispatchCancellations = LockedCounter()
        let onDispatchCancellation: @Sendable () -> Void = {
            dispatchCancellations.increment()
        }
        let pendingCandidate = await coordinator.registerProviderDispatch(
            authorization,
            for: .translation,
            onCancellation: onDispatchCancellation
        )
        let pending = try #require(pendingCandidate)
        let noOp: @Sendable () -> Void = {}
        let completedCandidate = await coordinator.registerProviderDispatch(
            authorization,
            for: .transcription,
            onCancellation: noOp
        )
        let completed = try #require(completedCandidate)
        let didLaunch = await coordinator.launchProviderDispatch(
            completed,
            launch: noOp
        )
        #expect(didLaunch)
        let resultCancellations = LockedCounter()
        let onResultCancellation: @Sendable () -> Void = {
            resultCancellations.increment()
        }
        let resultCandidate = await coordinator.finishProviderDispatch(
            completed,
            onResultCancellation: onResultCancellation
        )
        let result = try #require(resultCandidate)

        try FileManager.default.moveItem(at: root, to: original)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )

        let commits = LockedCounter()
        let consume: @Sendable () -> Void = { commits.increment() }
        let consumed: Void? = await coordinator.consumeProviderResult(
            result,
            perform: consume
        )
        #expect(consumed == nil)
        #expect(commits.value == 0)
        #expect(dispatchCancellations.value == 1)
        #expect(resultCancellations.value == 1)
        let pendingDidLaunch = await coordinator.launchProviderDispatch(
            pending,
            launch: noOp
        )
        #expect(!pendingDidLaunch)
    }

    @Test func sameRootAcceptedReplacementRejectsRegistration() async throws {
        let record = try fixtureRecord(state: .accepted, revision: 1)
        let journal = IOSProviderConsentJournalFake(record: record)
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )

        journal.installExternally(record)

        let registration = await coordinator.registerProviderDispatch(
            authorization,
            for: .transcription,
            onCancellation: {}
        )
        #expect(registration == nil)
        #expect(coordinator.makeAuthorization(from: accepted) == nil)
    }

    @Test func sameRootWithdrawalCancelsBeforeLaunch() async throws {
        let record = try fixtureRecord(state: .accepted, revision: 1)
        let journal = IOSProviderConsentJournalFake(record: record)
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let cancellations = LockedCounter()
        let registration = try #require(
            await coordinator.registerProviderDispatch(
                authorization,
                for: .correction,
                onCancellation: { cancellations.increment() }
            )
        )
        journal.installExternally(
            try fixtureRecord(
                state: .withdrawn,
                revision: 2,
                epochID: record.epochID
            )
        )
        let launches = LockedCounter()

        let didLaunch = await coordinator.launchProviderDispatch(
            registration,
            launch: { launches.increment() }
        )

        #expect(!didLaunch)
        #expect(launches.value == 0)
        #expect(cancellations.value == 1)
    }

    @Test func sameRootUnreadableRecordCancelsBeforeResultHandoff()
        async throws {
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: 1)
        )
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let dispatchCancellations = LockedCounter()
        let registration = try #require(
            await coordinator.registerProviderDispatch(
                authorization,
                for: .translation,
                onCancellation: { dispatchCancellations.increment() }
            )
        )
        #expect(
            await coordinator.launchProviderDispatch(
                registration,
                launch: {}
            )
        )
        journal.installUnreadableExternally()

        let result = await coordinator.finishProviderDispatch(
            registration,
            onResultCancellation: {}
        )

        #expect(result == nil)
        #expect(dispatchCancellations.value == 1)
    }

    @Test func sameRootDeletionCancelsBeforeLaunch() async throws {
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: 1)
        )
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let cancellations = LockedCounter()
        let registration = try #require(
            await coordinator.registerProviderDispatch(
                authorization,
                for: .transcription,
                onCancellation: { cancellations.increment() }
            )
        )
        journal.removeExternally()

        let didLaunch = await coordinator.launchProviderDispatch(
            registration,
            launch: {}
        )

        #expect(!didLaunch)
        #expect(cancellations.value == 1)
    }

    @Test func sameRootUnavailabilityCancelsBeforeResultConsumption()
        async throws {
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: 1)
        )
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let registration = try #require(
            await coordinator.registerProviderDispatch(
                authorization,
                for: .transcription,
                onCancellation: {}
            )
        )
        #expect(
            await coordinator.launchProviderDispatch(
                registration,
                launch: {}
            )
        )
        let resultCancellations = LockedCounter()
        let result = try #require(
            await coordinator.finishProviderDispatch(
                registration,
                onResultCancellation: {
                    resultCancellations.increment()
                }
            )
        )
        journal.loadError = .localDataUnavailable
        let commits = LockedCounter()

        let consumed: Void? = await coordinator.consumeProviderResult(
            result,
            perform: { commits.increment() }
        )

        #expect(consumed == nil)
        #expect(commits.value == 0)
        #expect(resultCancellations.value == 1)
    }

    @Test func finalRootAdmissionRejectsSubstitutionBeforeLaunch()
        async throws {
        let expectedRoot = IOSPersistenceRepositoryRootIdentity(
            device: 101,
            inode: 201
        )
        let replacementRoot = IOSPersistenceRepositoryRootIdentity(
            device: 101,
            inode: 202
        )
        let probe = IOSProviderConsentRepositoryAdmissionProbe(
            expectedRoot: expectedRoot
        )
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: 1)
        )
        let coordinator = makeCoordinator(
            journal: journal,
            expectedRepositoryRootIdentity: expectedRoot,
            repositoryAdmissionRevalidation: { probe.revalidate() }
        )
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let cancellations = LockedCounter()
        let registration = try #require(
            await coordinator.registerProviderDispatch(
                authorization,
                for: .translation,
                onCancellation: { cancellations.increment() }
            )
        )
        probe.substituteOnNextFinalCheck(with: replacementRoot)
        let launches = LockedCounter()

        let didLaunch = await coordinator.launchProviderDispatch(
            registration,
            launch: { launches.increment() }
        )

        #expect(!didLaunch)
        #expect(launches.value == 0)
        #expect(cancellations.value == 1)
    }

    @Test func postValidationRootSubstitutionCannotReachGateTransition()
        async throws {
        let expectedRoot = IOSPersistenceRepositoryRootIdentity(
            device: 301,
            inode: 401
        )
        let replacementRoot = IOSPersistenceRepositoryRootIdentity(
            device: 301,
            inode: 402
        )
        let currentRoot = LockedBox<IOSPersistenceRepositoryRootIdentity?>(
            expectedRoot
        )
        let interposition = IOSProviderConsentOneShotInterposition()
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: 1)
        )
        let coordinator = makeCoordinator(
            journal: journal,
            expectedRepositoryRootIdentity: expectedRoot,
            repositoryAdmissionRevalidation: { currentRoot.value },
            providerAdmissionInterposition: { interposition.invoke() }
        )
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let cancellations = LockedCounter()
        let registration = try #require(
            await coordinator.registerProviderDispatch(
                authorization,
                for: .translation,
                onCancellation: { cancellations.increment() }
            )
        )
        interposition.arm {
            currentRoot.set(replacementRoot)
        }
        let launches = LockedCounter()

        let didLaunch = await coordinator.launchProviderDispatch(
            registration,
            launch: { launches.increment() }
        )

        #expect(!didLaunch)
        #expect(launches.value == 0)
        #expect(cancellations.value == 1)
    }

    @Test func repositoryAdmissionLeaseCoversEveryGateTransition()
        async throws {
        for phase in IOSProviderConsentAdmissionPhase.allCases {
            let record = try fixtureRecord(
                state: .accepted,
                revision: 1
            )
            let withdrawn = try fixtureRecord(
                state: .withdrawn,
                revision: 2,
                epochID: record.epochID
            )
            let journal = IOSProviderConsentJournalFake(record: record)
            let interposition = IOSProviderConsentOneShotInterposition()
            let coordinator = makeCoordinator(
                journal: journal,
                providerAdmissionInterposition: {
                    interposition.invoke()
                }
            )
            let accepted = await coordinator.observe()
            let authorization = try #require(
                coordinator.makeAuthorization(from: accepted)
            )
            let dispatchCancellations = LockedCounter()
            let resultCancellations = LockedCounter()
            var registration: IOSProviderConsentDispatchRegistration?
            var result: IOSProviderConsentResultAuthorization?

            if phase.rawValue
                >= IOSProviderConsentAdmissionPhase.launch.rawValue {
                registration = await coordinator.registerProviderDispatch(
                    authorization,
                    for: .transcription,
                    onCancellation: {
                        dispatchCancellations.increment()
                    }
                )
                #expect(registration != nil)
            }
            if phase.rawValue
                >= IOSProviderConsentAdmissionPhase.finish.rawValue {
                #expect(
                    await coordinator.launchProviderDispatch(
                        try #require(registration),
                        launch: {}
                    )
                )
            }
            if phase.rawValue
                >= IOSProviderConsentAdmissionPhase.consume.rawValue {
                result = await coordinator.finishProviderDispatch(
                    try #require(registration),
                    onResultCancellation: {
                        resultCancellations.increment()
                    }
                )
                #expect(result != nil)
            }

            let mutationRace = IOSProviderConsentAdmissionMutationRace {
                journal.installExternally(withdrawn)
            }
            interposition.arm { mutationRace.interpose() }

            switch phase {
            case .register:
                registration = await coordinator.registerProviderDispatch(
                    authorization,
                    for: .transcription,
                    onCancellation: {
                        dispatchCancellations.increment()
                    }
                )
                #expect(registration != nil)
            case .launch:
                #expect(
                    await coordinator.launchProviderDispatch(
                        try #require(registration),
                        launch: {}
                    )
                )
            case .finish:
                result = await coordinator.finishProviderDispatch(
                    try #require(registration),
                    onResultCancellation: {
                        resultCancellations.increment()
                    }
                )
                #expect(result != nil)
            case .consume:
                let consumed = await coordinator.consumeProviderResult(
                    try #require(result),
                    perform: { 42 }
                )
                #expect(consumed == 42)
            }

            #expect(mutationRace.didStartInTime)
            #expect(!mutationRace.didFinishInsideLease)
            #expect(mutationRace.waitForCompletion())
            #expect(journal.currentRecord == withdrawn)

            switch phase {
            case .register, .launch:
                let lateResult = await coordinator.finishProviderDispatch(
                    try #require(registration),
                    onResultCancellation: {}
                )
                #expect(lateResult == nil)
                #expect(dispatchCancellations.value == 1)
            case .finish:
                let consumed: Int? = await coordinator.consumeProviderResult(
                    try #require(result),
                    perform: { 42 }
                )
                #expect(consumed == nil)
                #expect(resultCancellations.value == 1)
            case .consume:
                let lateRegistration = await coordinator
                    .registerProviderDispatch(
                        authorization,
                        for: .translation,
                        onCancellation: {}
                    )
                #expect(lateRegistration == nil)
                #expect(resultCancellations.value == 0)
            }
        }
    }

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
            let onCancellation: @Sendable () -> Void = {}
            let registrationCandidate = await coordinator.registerProviderDispatch(
                authorization,
                for: stage,
                onCancellation: onCancellation
            )
            let registration = try #require(registrationCandidate)
            let launches = LockedCounter()
            let launch: @Sendable () -> Void = { launches.increment() }
            let didLaunch = await coordinator.launchProviderDispatch(
                registration,
                launch: launch
            )
            #expect(didLaunch)
            #expect(launches.value == 1)
            let resultCandidate = await coordinator.finishProviderDispatch(
                registration,
                onResultCancellation: onCancellation
            )
            let result = try #require(resultCandidate)
            let consume: @Sendable () -> IOSProviderConsentProviderStage = {
                stage
            }
            let consumedCandidate = await coordinator.consumeProviderResult(
                result,
                perform: consume
            )
            let consumed = try #require(consumedCandidate)
            #expect(consumed == stage)
            let repeatedConsumption = await coordinator.consumeProviderResult(
                result,
                perform: consume
            )
            #expect(repeatedConsumption == nil)
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
        let cancellation = LockedCounter()
        let onCancellation: @Sendable () -> Void = {
            cancellation.increment()
        }
        let registrationCandidate = await coordinator.registerProviderDispatch(
            oldAuthorization,
            for: .transcription,
            onCancellation: onCancellation
        )
        let registration = try #require(registrationCandidate)
        let launch: @Sendable () -> Void = {}
        let didLaunch = await coordinator.launchProviderDispatch(
            registration,
            launch: launch
        )
        #expect(didLaunch)

        let withdrawn = try await coordinator.withdraw(
            using: accepted,
            decisionAt: try fixtureDate("2026-07-12T10:01:00.000Z")
        )

        #expect(withdrawn.status == .withdrawn)
        #expect(cancellation.value == 1)
        let lateRegistration = await coordinator.registerProviderDispatch(
            oldAuthorization,
            for: .transcription,
            onCancellation: launch
        )
        #expect(lateRegistration == nil)
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

    @Test func queuedAcceptanceCannotWriteAfterNoOpWithdrawalClosesGate()
        async throws {
        let record = try fixtureRecord(state: .withdrawn, revision: 9)
        let journal = IOSProviderConsentJournalFake(record: record)
        let coordinator = makeCoordinator(journal: journal)
        let observation = await coordinator.observe()
        let originalFence = try #require(observation.gateFence)
        let loadBlock = journal.blockNextLoad()
        defer { loadBlock.release() }
        let blockedObservation = Task.detached(priority: .background) {
            await coordinator.observe()
        }
        try #require(loadBlock.waitUntilEntered())

        let acceptanceStarted = IOSProviderConsentSignal()
        let acceptance = Task.detached(priority: .high) {
            acceptanceStarted.signal()
            return try await coordinator.accept(using: observation)
        }
        try #require(acceptanceStarted.wait())
        for _ in 0..<64 { await Task.yield() }

        let withdrawalStarted = IOSProviderConsentSignal()
        let withdrawal = Task.detached(priority: .low) {
            withdrawalStarted.signal()
            return try await coordinator.withdraw(using: observation)
        }
        try #require(withdrawalStarted.wait())
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while coordinator.testingCurrentGateFence() == originalFence,
              clock.now < deadline {
            await Task.yield()
        }
        #expect(coordinator.testingCurrentGateFence() != originalFence)

        loadBlock.release()
        _ = await blockedObservation.value
        let withdrawn = try await withdrawal.value
        #expect(withdrawn.status == .withdrawn)
        await #expect(throws: IOSProviderConsentError.staleObservation) {
            _ = try await acceptance.value
        }
        #expect(journal.currentRecord == record)
        #expect(journal.replaceCallCount == 0)
    }

    @Test func queuedAcceptanceCannotWriteAfterFailedWithdrawalClosesGate()
        async throws {
        let record = try fixtureRecord(
            state: .accepted,
            revision: 4,
            disclosureVersion: 1
        )
        let journal = IOSProviderConsentJournalFake(record: record)
        let coordinator = IOSProviderConsentCoordinator(
            journal: journal,
            currentDisclosureVersion: 2
        )
        let observation = await coordinator.observe()
        #expect(observation.status == .reviewRequired)
        let originalFence = try #require(observation.gateFence)
        let loadBlock = journal.blockNextLoad()
        defer { loadBlock.release() }
        let blockedObservation = Task.detached(priority: .background) {
            await coordinator.observe()
        }
        try #require(loadBlock.waitUntilEntered())
        journal.nextMutation = .failBeforeCommit(.mutationNotSaved)

        let acceptanceStarted = IOSProviderConsentSignal()
        let acceptance = Task.detached(priority: .high) {
            acceptanceStarted.signal()
            return try await coordinator.accept(using: observation)
        }
        try #require(acceptanceStarted.wait())
        for _ in 0..<64 { await Task.yield() }

        let withdrawalStarted = IOSProviderConsentSignal()
        let withdrawal = Task.detached(priority: .low) {
            withdrawalStarted.signal()
            return try await coordinator.withdraw(using: observation)
        }
        try #require(withdrawalStarted.wait())
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while coordinator.testingCurrentGateFence() == originalFence,
              clock.now < deadline {
            await Task.yield()
        }
        #expect(coordinator.testingCurrentGateFence() != originalFence)

        loadBlock.release()
        _ = await blockedObservation.value
        await #expect(throws: IOSProviderConsentError.mutationNotSaved) {
            _ = try await withdrawal.value
        }
        await #expect(throws: IOSProviderConsentError.staleObservation) {
            _ = try await acceptance.value
        }
        #expect(journal.currentRecord == record)
        #expect(journal.replaceCallCount == 1)
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

        let resetObservation = await coordinator.observe()
        let reset = try await coordinator.resetUnreadableConsentData(
            using: resetObservation
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

    @Test func authoritativePassiveChangeRotatesObservationFence() async throws {
        let record = try fixtureRecord(state: .accepted, revision: 1)
        let journal = IOSProviderConsentJournalFake(record: record)
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        #expect(coordinator.makeAuthorization(from: accepted) != nil)

        journal.installExternally(
            try fixtureRecord(
                state: .withdrawn,
                revision: 2,
                epochID: record.epochID
            )
        )
        let withdrawn = await coordinator.observe()

        #expect(withdrawn.status == .withdrawn)
        #expect(accepted.gateFence != withdrawn.gateFence)
        #expect(coordinator.makeAuthorization(from: accepted) == nil)
        await #expect(throws: IOSProviderConsentError.staleObservation) {
            _ = try await coordinator.accept(using: accepted)
        }
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

    @Test func firstProcessAuthorizationRequiresDirectoryDurabilityConfirmation()
        async throws {
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: 7)
        )
        journal.synchronizeError = .commitUncertain
        let coordinator = makeCoordinator(journal: journal)

        let blocked = await coordinator.observe()
        #expect(blocked.status == .localDataUnavailable)
        #expect(coordinator.makeAuthorization(from: blocked) == nil)
        #expect(journal.synchronizeCallCount == 1)

        journal.synchronizeError = nil
        let confirmed = await coordinator.observe()
        #expect(confirmed.status == .acceptedCurrentDisclosure)
        #expect(coordinator.makeAuthorization(from: confirmed) != nil)
        #expect(journal.synchronizeCallCount == 2)

        _ = await coordinator.observe()
        #expect(journal.synchronizeCallCount == 2)
    }

    @Test func withdrawalCancelsRegisteredDispatchBeforeItCanLaunch() async throws {
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: 1)
        )
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let cancellations = LockedCounter()
        let onCancellation: @Sendable () -> Void = {
            cancellations.increment()
        }
        let registrationCandidate = await coordinator.registerProviderDispatch(
            authorization,
            for: .correction,
            onCancellation: onCancellation
        )
        let registration = try #require(registrationCandidate)

        _ = try await coordinator.withdraw(using: accepted)

        #expect(cancellations.value == 1)
        let launch: @Sendable () -> Void = {}
        let didLaunch = await coordinator.launchProviderDispatch(
            registration,
            launch: launch
        )
        #expect(!didLaunch)
        let lateResult = await coordinator.finishProviderDispatch(
            registration,
            onResultCancellation: launch
        )
        #expect(lateResult == nil)
    }

    @Test func withdrawalRejectsNoncooperativeLateResultBeforeConsumption()
        async throws {
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: 1)
        )
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let dispatchCancellations = LockedCounter()
        let resultCancellations = LockedCounter()
        let onDispatchCancellation: @Sendable () -> Void = {
            dispatchCancellations.increment()
        }
        let registrationCandidate = await coordinator.registerProviderDispatch(
            authorization,
            for: .translation,
            onCancellation: onDispatchCancellation
        )
        let registration = try #require(registrationCandidate)
        let launch: @Sendable () -> Void = {}
        let didLaunch = await coordinator.launchProviderDispatch(
            registration,
            launch: launch
        )
        #expect(didLaunch)
        let onResultCancellation: @Sendable () -> Void = {
            resultCancellations.increment()
        }
        let resultCandidate = await coordinator.finishProviderDispatch(
            registration,
            onResultCancellation: onResultCancellation
        )
        let result = try #require(resultCandidate)

        _ = try await coordinator.withdraw(using: accepted)

        #expect(dispatchCancellations.value == 0)
        #expect(resultCancellations.value == 1)
        let commits = LockedCounter()
        let consume: @Sendable () -> Void = { commits.increment() }
        let consumed: Void? = await coordinator.consumeProviderResult(
            result,
            perform: consume
        )
        #expect(consumed == nil)
        #expect(commits.value == 0)
    }

    @Test func resultConsumptionIsOneShotAndLocalFailureRemainsRetryable()
        async throws {
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: 1)
        )
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let noOp: @Sendable () -> Void = {}
        let registrationCandidate = await coordinator.registerProviderDispatch(
            authorization,
            for: .transcription,
            onCancellation: noOp
        )
        let registration = try #require(registrationCandidate)
        let didLaunch = await coordinator.launchProviderDispatch(
            registration,
            launch: noOp
        )
        #expect(didLaunch)
        let resultCandidate = await coordinator.finishProviderDispatch(
            registration,
            onResultCancellation: noOp
        )
        let result = try #require(resultCandidate)

        let failCommit: @Sendable () throws -> Int = {
            throw IOSProviderConsentTestError.localCommitFailed
        }
        await #expect(throws: IOSProviderConsentTestError.localCommitFailed) {
            _ = try await coordinator.consumeProviderResult(
                result,
                perform: failCommit
            )
        }
        let successfulCommit: @Sendable () -> Int = { 42 }
        let committed = await coordinator.consumeProviderResult(
            result,
            perform: successfulCommit
        )
        #expect(committed == 42)
        let repeatedCommit: @Sendable () -> Int = { 43 }
        let repeated = await coordinator.consumeProviderResult(
            result,
            perform: repeatedCommit
        )
        #expect(repeated == nil)
    }

    @Test func launchCallbackCanCancelAcrossExecutorWithoutDeadlock()
        async throws {
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: 1)
        )
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let cancellations = LockedCounter()
        let registration = try #require(
            await coordinator.registerProviderDispatch(
                authorization,
                for: .transcription,
                onCancellation: { cancellations.increment() }
            )
        )
        let reentryStarted = LockedBox(false)
        let reentryCompleted = LockedBox(false)

        let didLaunch = await coordinator.launchProviderDispatch(
            registration,
            launch: {
                let started = DispatchSemaphore(value: 0)
                let completed = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .userInitiated).async {
                    started.signal()
                    coordinator.cancelProviderDispatch(registration)
                    completed.signal()
                }
                reentryStarted.set(
                    started.wait(timeout: .now() + 1) == .success
                )
                reentryCompleted.set(
                    completed.wait(timeout: .now() + 1) == .success
                )
            }
        )

        #expect(didLaunch)
        #expect(reentryStarted.value)
        #expect(reentryCompleted.value)
        #expect(cancellations.value == 1)
        let lateResult = await coordinator.finishProviderDispatch(
            registration,
            onResultCancellation: {}
        )
        #expect(lateResult == nil)
    }

    @Test func resultCallbackCanInvalidateAcrossExecutorWithoutDeadlock()
        async throws {
        let journal = IOSProviderConsentJournalFake(
            record: try fixtureRecord(state: .accepted, revision: 1)
        )
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let registration = try #require(
            await coordinator.registerProviderDispatch(
                authorization,
                for: .translation,
                onCancellation: {}
            )
        )
        #expect(
            await coordinator.launchProviderDispatch(
                registration,
                launch: {}
            )
        )
        let resultCancellations = LockedCounter()
        let result = try #require(
            await coordinator.finishProviderDispatch(
                registration,
                onResultCancellation: {
                    resultCancellations.increment()
                }
            )
        )
        let reentryStarted = LockedBox(false)
        let reentryCompleted = LockedBox(false)

        let consumed = await coordinator.consumeProviderResult(
            result,
            perform: {
                let started = DispatchSemaphore(value: 0)
                let completed = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .userInitiated).async {
                    started.signal()
                    coordinator.invalidateProviderAuthorizations()
                    completed.signal()
                }
                reentryStarted.set(
                    started.wait(timeout: .now() + 1) == .success
                )
                reentryCompleted.set(
                    completed.wait(timeout: .now() + 1) == .success
                )
                return 42
            }
        )

        #expect(consumed == 42)
        #expect(reentryStarted.value)
        #expect(reentryCompleted.value)
        #expect(resultCancellations.value == 0)
        let lateRegistration = await coordinator.registerProviderDispatch(
            authorization,
            for: .translation,
            onCancellation: {}
        )
        #expect(lateRegistration == nil)
    }

    @Test func withdrawalClosesGateEvenWhenRepositoryMutationFails() async throws {
        let record = try fixtureRecord(state: .accepted, revision: 1)
        let journal = IOSProviderConsentJournalFake(record: record)
        let coordinator = makeCoordinator(journal: journal)
        let accepted = await coordinator.observe()
        let authorization = try #require(
            coordinator.makeAuthorization(from: accepted)
        )
        let cancellation = LockedCounter()
        let onCancellation: @Sendable () -> Void = {
            cancellation.increment()
        }
        let registrationCandidate = await coordinator.registerProviderDispatch(
            authorization,
            for: .translation,
            onCancellation: onCancellation
        )
        let registration = try #require(registrationCandidate)

        journal.nextMutation = .failBeforeCommit(.mutationNotSaved)
        await #expect(throws: IOSProviderConsentError.mutationNotSaved) {
            _ = try await coordinator.withdraw(
                using: accepted,
                decisionAt: try fixtureDate("2026-07-12T13:00:00.000Z")
            )
        }
        #expect(cancellation.value == 1)
        let launch: @Sendable () -> Void = {}
        let didLaunch = await coordinator.launchProviderDispatch(
            registration,
            launch: launch
        )
        #expect(!didLaunch)
        await #expect(throws: IOSProviderConsentError.staleObservation) {
            _ = try await coordinator.accept(using: accepted)
        }

        let fresh = await coordinator.observe()
        let reopened = try await coordinator.accept(using: fresh)
        #expect(coordinator.makeAuthorization(from: reopened) != nil)
    }

    @Test func passiveBindingReplacementAndRemovalCancelRegisteredDispatches()
        throws {
        let gate = IOSProviderConsentAuthorizationGate()
        let ownerIdentity = IOSProviderConsentOwnerIdentity()
        let firstBinding = IOSProviderConsentAuthorizationBinding(
            ownerIdentity: ownerIdentity,
            epochID: UUID(),
            revision: 1,
            disclosureVersion: 1
        )
        let secondBinding = IOSProviderConsentAuthorizationBinding(
            ownerIdentity: ownerIdentity,
            epochID: firstBinding.epochID,
            revision: 2,
            disclosureVersion: 1
        )
        let fence = gate.currentFence()
        let firstFence = try #require(
            gate.adoptPassively(
                binding: firstBinding,
                ifFenceIs: fence
            )
        )
        let firstAuthorization = try #require(
            gate.makeAuthorization(for: firstBinding)
        )
        let cancellations = LockedCounter()
        let onCancellation: @Sendable () -> Void = {
            cancellations.increment()
        }
        let firstRegistrationCandidate = gate.registerDispatch(
            firstAuthorization,
            stage: .transcription,
            onCancellation: onCancellation
        )
        let firstRegistration = try #require(firstRegistrationCandidate)

        let secondFence = try #require(
            gate.adoptPassively(
                binding: secondBinding,
                ifFenceIs: firstFence
            )
        )

        #expect(cancellations.value == 1)
        let noOp: @Sendable () -> Void = {}
        let firstDidLaunch = gate.launchDispatch(
            firstRegistration,
            launch: noOp
        )
        #expect(!firstDidLaunch)
        let secondAuthorization = try #require(
            gate.makeAuthorization(for: secondBinding)
        )
        let secondRegistrationCandidate = gate.registerDispatch(
            secondAuthorization,
            stage: .translation,
            onCancellation: onCancellation
        )
        _ = try #require(secondRegistrationCandidate)

        _ = gate.adoptPassively(
            binding: nil,
            ifFenceIs: secondFence
        )

        #expect(cancellations.value == 2)
        #expect(gate.makeAuthorization(for: secondBinding) == nil)
    }

    @Test func explicitBindingReplacementCancelsUnconsumedProviderResult()
        throws {
        let gate = IOSProviderConsentAuthorizationGate()
        let ownerIdentity = IOSProviderConsentOwnerIdentity()
        let firstBinding = IOSProviderConsentAuthorizationBinding(
            ownerIdentity: ownerIdentity,
            epochID: UUID(),
            revision: 1,
            disclosureVersion: 1
        )
        let secondBinding = IOSProviderConsentAuthorizationBinding(
            ownerIdentity: ownerIdentity,
            epochID: firstBinding.epochID,
            revision: 2,
            disclosureVersion: 1
        )
        let fence = gate.currentFence()
        let firstFence = try #require(
            gate.adoptPassively(
                binding: firstBinding,
                ifFenceIs: fence
            )
        )
        let authorization = try #require(
            gate.makeAuthorization(for: firstBinding)
        )
        let noOp: @Sendable () -> Void = {}
        let registrationCandidate = gate.registerDispatch(
            authorization,
            stage: .correction,
            onCancellation: noOp
        )
        let registration = try #require(registrationCandidate)
        let didLaunch = gate.launchDispatch(registration, launch: noOp)
        #expect(didLaunch)
        let resultCancellations = LockedCounter()
        let onResultCancellation: @Sendable () -> Void = {
            resultCancellations.increment()
        }
        let resultCandidate = gate.finishDispatch(
            registration,
            onResultCancellation: onResultCancellation
        )
        let result = try #require(resultCandidate)

        _ = gate.adoptAfterExplicitAcceptance(
            binding: secondBinding,
            ifFenceIs: firstFence
        )

        #expect(resultCancellations.value == 1)
        let commits = LockedCounter()
        let consume: @Sendable () -> Void = { commits.increment() }
        let consumed: Void? = gate.consumeResult(result, perform: consume)
        #expect(consumed == nil)
        #expect(commits.value == 0)
        #expect(gate.makeAuthorization(for: secondBinding) != nil)
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
        _ = gate.adoptPassively(
            binding: binding,
            ifFenceIs: originalFence
        )
        let originalAuthorization = gate.makeAuthorization(for: binding)
        #expect(originalAuthorization != nil)

        gate.close()
        let noOp: @Sendable () -> Void = {}
        let registration = originalAuthorization.flatMap {
            gate.registerDispatch(
                $0,
                stage: .transcription,
                onCancellation: noOp
            )
        }
        #expect(registration == nil)

        _ = gate.adoptAfterExplicitAcceptance(
            binding: binding,
            ifFenceIs: originalFence
        )
        #expect(gate.makeAuthorization(for: binding) == nil)

        let currentFence = gate.currentFence()
        _ = gate.adoptPassively(
            binding: binding,
            ifFenceIs: currentFence
        )
        #expect(gate.makeAuthorization(for: binding) == nil)

        _ = gate.adoptAfterExplicitAcceptance(
            binding: binding,
            ifFenceIs: currentFence
        )
        let acceptedAuthorization = gate.makeAuthorization(for: binding)
        #expect(acceptedAuthorization != nil)

        // The explicit acceptance rotated the fence. A delayed failure or
        // passive observation carrying the old fence cannot close or replace it.
        gate.close(ifFenceIs: currentFence)
        _ = gate.adoptPassively(
            binding: nil,
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
        let noOp: @Sendable () -> Void = {}
        let registrationCandidate = await coordinator.registerProviderDispatch(
            authorization,
            for: .transcription,
            onCancellation: noOp
        )
        let registration = try #require(registrationCandidate)
        let didLaunch = await coordinator.launchProviderDispatch(
            registration,
            launch: noOp
        )
        #expect(didLaunch)
        let resultCandidate = await coordinator.finishProviderDispatch(
            registration,
            onResultCancellation: noOp
        )
        let result = try #require(resultCandidate)
        let values: [Any] = [
            coordinator,
            observation,
            authorization,
            registration,
            result,
            observation.source,
            try #require(observation.gateFence),
            try #require(journal.snapshot),
        ]

        for value in values {
            var rendered = canary
            dump(value, to: &rendered)
            #expect(!String(describing: value).contains(canary))
            #expect(!String(reflecting: value).contains(canary))
            #expect(rendered.filter { $0 == "\n" }.count <= 1)
        }
        coordinator.abandonProviderResult(result)
    }

    private func makeCoordinator(
        journal: IOSProviderConsentJournalFake,
        epoch: UUID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!,
        expectedRepositoryRootIdentity:
            IOSPersistenceRepositoryRootIdentity? = nil,
        repositoryAdmissionRevalidation:
            @escaping @Sendable () throws
                -> IOSPersistenceRepositoryRootIdentity? = { nil },
        providerAdmissionInterposition:
            @escaping @Sendable () -> Void = {}
    ) -> IOSProviderConsentCoordinator {
        IOSProviderConsentCoordinator(
            journal: journal,
            currentDisclosureVersion: 1,
            makeEpochID: { epoch },
            expectedRepositoryRootIdentity:
                expectedRepositoryRootIdentity,
            repositoryAdmissionRevalidation:
                repositoryAdmissionRevalidation,
            providerAdmissionInterposition:
                providerAdmissionInterposition
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

    private let admissionGuard = IOSProviderConsentRepositoryAdmissionGuard()
    private let lock = NSLock()
    private var storedSnapshot: IOSProviderConsentJournalSnapshot?
    private var nextTestingRevision: UInt64 = 100
    private var storedLoadCallCount = 0
    private var storedCreateCallCount = 0
    private var storedReplaceCallCount = 0
    private var storedRemoveCallCount = 0
    private var storedSynchronizeCallCount = 0
    private var nextLoadBlock: IOSProviderConsentJournalLoadBlock?
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
        try admissionGuard.withLease {
            try loadWithoutAdmissionLease()
        }
    }

    func blockNextLoad() -> IOSProviderConsentJournalLoadBlock {
        let loadBlock = IOSProviderConsentJournalLoadBlock()
        lock.withLock {
            precondition(nextLoadBlock == nil)
            nextLoadBlock = loadBlock
        }
        return loadBlock
    }

    func withProviderAdmissionLease<Result>(
        _ operation: (
            IOSProviderConsentJournalSnapshot?
        ) throws -> Result
    ) throws -> Result {
        try admissionGuard.withLease {
            try operation(try loadWithoutAdmissionLease())
        }
    }

    func create(_ record: IOSProviderConsentRecord) throws
        -> IOSProviderConsentJournalSnapshot {
        try admissionGuard.withLease {
            try lock.withLock {
                storedCreateCallCount += 1
                guard storedSnapshot == nil else {
                    throw IOSProviderConsentJournalError.staleRevision
                }
                return try applyMutation(intended: record)
            }
        }
    }

    func replace(
        _ record: IOSProviderConsentRecord,
        expected: IOSProviderConsentJournalSnapshot
    ) throws -> IOSProviderConsentJournalSnapshot {
        return try admissionGuard.withLease {
            try lock.withLock {
                storedReplaceCallCount += 1
                guard storedSnapshot == expected else {
                    throw IOSProviderConsentJournalError.staleRevision
                }
                return try applyMutation(intended: record)
            }
        }
    }

    func removeUnreadable(
        expected: IOSProviderConsentJournalSnapshot
    ) throws {
        try admissionGuard.withLease {
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
    }

    func synchronizeDirectory() throws {
        try admissionGuard.withLease {
            try lock.withLock {
                storedSynchronizeCallCount += 1
                if let synchronizeError { throw synchronizeError }
            }
        }
    }

    func installExternally(_ record: IOSProviderConsentRecord) {
        admissionGuard.withLease {
            lock.withLock {
                storedSnapshot = mintSnapshot(record)
            }
        }
    }

    func installUnreadableExternally() {
        admissionGuard.withLease {
            lock.withLock {
                storedSnapshot = IOSProviderConsentJournalSnapshot(
                    content: .unreadable,
                    testingRevision: nextTestingRevision
                )
                nextTestingRevision += 1
            }
        }
    }

    func removeExternally() {
        admissionGuard.withLease {
            lock.withLock {
                storedSnapshot = nil
            }
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

    private func loadWithoutAdmissionLease() throws
        -> IOSProviderConsentJournalSnapshot? {
        let loadBlock = lock.withLock { ()
            -> IOSProviderConsentJournalLoadBlock? in
            storedLoadCallCount += 1
            defer { nextLoadBlock = nil }
            return nextLoadBlock
        }
        loadBlock?.waitUntilReleased()
        return try lock.withLock {
            if let loadError { throw loadError }
            return storedSnapshot
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

private final class IOSProviderConsentRepositoryAdmissionProbe:
    @unchecked Sendable {
    private let lock = NSLock()
    private let expectedRoot: IOSPersistenceRepositoryRootIdentity
    private var replacementRoot: IOSPersistenceRepositoryRootIdentity?
    private var revalidationCount = 0

    init(expectedRoot: IOSPersistenceRepositoryRootIdentity) {
        self.expectedRoot = expectedRoot
    }

    func substituteOnNextFinalCheck(
        with replacementRoot: IOSPersistenceRepositoryRootIdentity
    ) {
        lock.withLock {
            self.replacementRoot = replacementRoot
            revalidationCount = 0
        }
    }

    func revalidate() -> IOSPersistenceRepositoryRootIdentity? {
        lock.withLock {
            guard let replacementRoot else { return expectedRoot }
            revalidationCount += 1
            return revalidationCount >= 2
                ? replacementRoot
                : expectedRoot
        }
    }
}

private enum IOSProviderConsentAdmissionPhase: Int, CaseIterable {
    case register
    case launch
    case finish
    case consume
}

private enum IOSProviderConsentTestError: Error {
    case localCommitFailed
}

private final class IOSProviderConsentJournalLoadBlock: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)

    func waitUntilReleased() {
        entered.signal()
        _ = releaseSignal.wait(timeout: .now() + 5)
    }

    func waitUntilEntered() -> Bool {
        entered.wait(timeout: .now() + 2) == .success
    }

    func release() {
        releaseSignal.signal()
    }
}

private final class IOSProviderConsentSignal: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    func signal() {
        semaphore.signal()
    }

    func wait() -> Bool {
        semaphore.wait(timeout: .now() + 2) == .success
    }
}

private final class IOSProviderConsentOneShotInterposition:
    @unchecked Sendable {
    private let lock = NSLock()
    private var operation: (@Sendable () -> Void)?

    func arm(_ operation: @escaping @Sendable () -> Void) {
        lock.withLock {
            precondition(self.operation == nil)
            self.operation = operation
        }
    }

    func invoke() {
        let operation = lock.withLock { () -> (@Sendable () -> Void)? in
            defer { self.operation = nil }
            return self.operation
        }
        operation?()
    }
}

private final class IOSProviderConsentAdmissionMutationRace:
    @unchecked Sendable {
    private let operation: @Sendable () -> Void
    private let started = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private let startedInTime = LockedBox(false)
    private let finishedInsideLease = LockedBox(false)

    init(operation: @escaping @Sendable () -> Void) {
        self.operation = operation
    }

    func interpose() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.started.signal()
            self.operation()
            self.finished.signal()
        }
        startedInTime.set(
            started.wait(timeout: .now() + 2) == .success
        )
        finishedInsideLease.set(
            finished.wait(timeout: .now() + 0.05) == .success
        )
    }

    var didStartInTime: Bool { startedInTime.value }
    var didFinishInsideLease: Bool { finishedInsideLease.value }

    func waitForCompletion() -> Bool {
        if finishedInsideLease.value { return true }
        return finished.wait(timeout: .now() + 2) == .success
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value { lock.withLock { storedValue } }

    func set(_ value: Value) {
        lock.withLock { storedValue = value }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int { lock.withLock { storedValue } }

    func increment() {
        lock.withLock {
            storedValue += 1
        }
    }
}
