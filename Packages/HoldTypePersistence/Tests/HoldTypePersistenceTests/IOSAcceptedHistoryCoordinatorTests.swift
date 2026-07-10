import Darwin
import Foundation
import Testing
import HoldTypeDomain
@testable import HoldTypePersistence

struct IOSAcceptedHistoryCoordinatorTests {
    @Test func productionContextRegistrySharesOnlyOnePhysicalRoot() async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-coordinator-\(UUID().uuidString)",
            isDirectory: true
        )
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let alias = parent.appendingPathComponent("alias", isDirectory: true)
        let equivalentRoot = root
            .appendingPathComponent("..")
            .appendingPathComponent("root")
        let otherRoot = parent.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: otherRoot,
            withIntermediateDirectories: false
        )
        try FileManager.default.createSymbolicLink(
            at: alias,
            withDestinationURL: root
        )
        defer { try? FileManager.default.removeItem(at: parent) }

        let first = registry.context(for: root)
        let sameRoot = registry.context(for: equivalentRoot)
        let symlinkAlias = registry.context(for: alias)
        let differentRoot = registry.context(for: otherRoot)
        let binding = registry.revalidate(context: first, for: root)

        #expect(first === sameRoot)
        #expect(first === symlinkAlias)
        #expect(first.policyStore === sameRoot.policyStore)
        #expect(first.acceptedHistoryStore === sameRoot.acceptedHistoryStore)
        #expect(first.outboxStore === sameRoot.outboxStore)
        #expect(first.deliveryStore === sameRoot.deliveryStore)
        #expect(first.baselineRecoveryState === sameRoot.baselineRecoveryState)
        #expect(first !== differentRoot)
        let renderedBinding = String(describing: binding)
            + String(reflecting: binding)
            + String(describing: Mirror(reflecting: binding))
        #expect(renderedBinding.contains("redacted"))
        #expect(!renderedBinding.contains(parent.path))
        #expect(
            first.baselineRecoveryState
                !== differentRoot.baselineRecoveryState
        )

        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        #expect(first === registry.context(for: root))

        let missingRoot = parent.appendingPathComponent(
            "initially-missing",
            isDirectory: true
        )
        let missing = registry.context(for: missingRoot)
        try FileManager.default.createDirectory(
            at: missingRoot,
            withIntermediateDirectories: false
        )
        #expect(missing === registry.context(for: missingRoot))
        #expect(missing.repositoryIdentityState.isConflicted)

        let caseAlias = parent.appendingPathComponent("ROOT", isDirectory: true)
        if coordinatorFileIdentity(root) == coordinatorFileIdentity(caseAlias) {
            #expect(first === registry.context(for: caseAlias))
        }

        let renameSource = parent.appendingPathComponent(
            "rename-source",
            isDirectory: true
        )
        let renameDestination = parent.appendingPathComponent(
            "rename-destination",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: renameSource,
            withIntermediateDirectories: false
        )
        let sourceContext = registry.context(for: renameSource)
        await sourceContext.baselineRecoveryState.requireRecovery()
        try FileManager.default.moveItem(
            at: renameSource,
            to: renameDestination
        )
        let destinationContext = registry.context(for: renameDestination)
        #expect(sourceContext !== destinationContext)
        #expect(sourceContext.repositoryIdentityState.isConflicted)
        #expect(destinationContext.repositoryIdentityState.isConflicted)

        let destinationRegistration =
            IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                registry: registry,
                context: destinationContext,
                applicationSupportDirectoryURL: renameDestination
            )
        let destinationFixture = CoordinatorFixture(
            repositoryIdentityState:
                destinationContext.repositoryIdentityState,
            repositoryRegistration: destinationRegistration
        )
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await destinationFixture.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(destinationFixture.policy.loadCount == 0)
        #expect(destinationFixture.accepted.loadCount == 0)
        #expect(destinationFixture.outbox.loadCount == 0)
        #expect(destinationFixture.delivery.loadCount == 0)
    }

    @Test func retargetedAliasNeverReusesItsPathPinnedContext() throws {
        for destinationWasRegistered in [false, true] {
            let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
            let parent = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "holdtype-coordinator-retarget-\(UUID().uuidString)",
                    isDirectory: true
                )
            let firstRoot = parent.appendingPathComponent("first", isDirectory: true)
            let secondRoot = parent.appendingPathComponent("second", isDirectory: true)
            let alias = parent.appendingPathComponent("alias", isDirectory: true)
            try FileManager.default.createDirectory(
                at: firstRoot,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: secondRoot,
                withIntermediateDirectories: false
            )
            try FileManager.default.createSymbolicLink(
                at: alias,
                withDestinationURL: firstRoot
            )
            defer { try? FileManager.default.removeItem(at: parent) }

            let first = registry.context(for: alias)
            let registeredSecond = destinationWasRegistered
                ? registry.context(for: secondRoot)
                : nil
            try FileManager.default.removeItem(at: alias)
            try FileManager.default.createSymbolicLink(
                at: alias,
                withDestinationURL: secondRoot
            )
            let second = registry.context(for: alias)

            #expect(first !== second)
            #expect(first.repositoryIdentityState.isConflicted)
            #expect(!second.repositoryIdentityState.isConflicted)
            if let registeredSecond {
                #expect(second === registeredSecond)
            }
        }
    }

    @Test func incompatibleRootOwnersFailBeforeStorageIO() async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-coordinator-conflict-\(UUID().uuidString)",
            isDirectory: true
        )
        let firstRoot = parent.appendingPathComponent("first", isDirectory: true)
        let secondRoot = parent.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(
            at: secondRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }

        let first = registry.context(for: firstRoot)
        let second = registry.context(for: secondRoot)
        let registration = IOSAcceptedHistoryCoordinatorRepositoryRegistration(
            registry: registry,
            context: first,
            applicationSupportDirectoryURL: firstRoot
        )
        try FileManager.default.createSymbolicLink(
            at: firstRoot,
            withDestinationURL: secondRoot
        )

        let fixture = CoordinatorFixture(
            repositoryIdentityState: first.repositoryIdentityState,
            repositoryRegistration: registration
        )
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await fixture.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(fixture.policy.loadCount == 0)
        #expect(fixture.accepted.loadCount == 0)
        #expect(fixture.outbox.loadCount == 0)
        #expect(fixture.delivery.loadCount == 0)
        #expect(first.repositoryIdentityState.isConflicted)
        #expect(second.repositoryIdentityState.isConflicted)
    }

    @Test func distinctRootsConvergingOnUnregisteredRootFailBeforeStorageIO() async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-coordinator-third-root-\(UUID().uuidString)",
            isDirectory: true
        )
        let firstRoot = parent.appendingPathComponent("first", isDirectory: true)
        let secondRoot = parent.appendingPathComponent("second", isDirectory: true)
        let destinationRoot = parent.appendingPathComponent(
            "destination",
            isDirectory: true
        )
        for root in [firstRoot, secondRoot, destinationRoot] {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: parent) }

        let first = registry.context(for: firstRoot)
        let second = registry.context(for: secondRoot)
        let registration = IOSAcceptedHistoryCoordinatorRepositoryRegistration(
            registry: registry,
            context: first,
            applicationSupportDirectoryURL: firstRoot
        )
        for root in [firstRoot, secondRoot] {
            try FileManager.default.removeItem(at: root)
            try FileManager.default.createSymbolicLink(
                at: root,
                withDestinationURL: destinationRoot
            )
        }
        let fixture = CoordinatorFixture(
            repositoryIdentityState: first.repositoryIdentityState,
            repositoryRegistration: registration
        )

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await fixture.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(first.repositoryIdentityState.isConflicted)
        #expect(second.repositoryIdentityState.isConflicted)
        #expect(fixture.policy.loadCount == 0)
        #expect(fixture.accepted.loadCount == 0)
        #expect(fixture.outbox.loadCount == 0)
        #expect(fixture.delivery.loadCount == 0)
    }

    @Test func missingRegisteredRootFailsBeforeStorageIO() async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-coordinator-missing-\(UUID().uuidString)",
            isDirectory: true
        )
        let context = registry.context(for: root)
        let registration = IOSAcceptedHistoryCoordinatorRepositoryRegistration(
            registry: registry,
            context: context,
            applicationSupportDirectoryURL: root
        )
        let fixture = CoordinatorFixture(
            repositoryIdentityState: context.repositoryIdentityState,
            repositoryRegistration: registration
        )

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await fixture.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(fixture.policy.loadCount == 0)
        #expect(fixture.accepted.loadCount == 0)
        #expect(fixture.outbox.loadCount == 0)
        #expect(fixture.delivery.loadCount == 0)
    }

    @Test func namespaceIdentityChangeDuringLeaseCannotIssueCapture() async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-coordinator-linearization-\(UUID().uuidString)",
            isDirectory: true
        )
        let root = parent.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }

        let context = registry.context(for: root)
        let registration = IOSAcceptedHistoryCoordinatorRepositoryRegistration(
            registry: registry,
            context: context,
            applicationSupportDirectoryURL: root
        )
        let fixture = CoordinatorFixture(
            repositoryIdentityState: context.repositoryIdentityState,
            repositoryRegistration: registration
        )
        let blocker = CoordinatorBoundaryBlocker()
        fixture.policy.loadBlocker = blocker
        let capture = Task {
            try await fixture.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(blocker.waitUntilBlocked())
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        blocker.open()

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await capture.value
        }
        #expect(context.repositoryIdentityState.isConflicted)
        #expect(fixture.policy.loadCount > 0)
    }

    @Test func identityChangeOverridesCommitUncertainAndTombstonesDestination() async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-coordinator-error-linearization-\(UUID().uuidString)",
            isDirectory: true
        )
        let sourceRoot = parent.appendingPathComponent("source", isDirectory: true)
        let destinationRoot = parent.appendingPathComponent(
            "destination",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destinationRoot,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: parent) }

        let sourceContext = registry.context(for: sourceRoot)
        let sourceRegistration =
            IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                registry: registry,
                context: sourceContext,
                applicationSupportDirectoryURL: sourceRoot
            )
        let sourceFixture = CoordinatorFixture(
            repositoryIdentityState: sourceContext.repositoryIdentityState,
            repositoryRegistration: sourceRegistration
        )
        let createBlocker = CoordinatorBoundaryBlocker()
        sourceFixture.policy.createBlocker = createBlocker
        sourceFixture.policy.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )
        let firstCapture = Task {
            try await sourceFixture.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(createBlocker.waitUntilBlocked())
        try FileManager.default.removeItem(at: sourceRoot)
        try FileManager.default.createSymbolicLink(
            at: sourceRoot,
            withDestinationURL: destinationRoot
        )
        createBlocker.open()

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await firstCapture.value
        }
        #expect(sourceFixture.policy.currentState == .baseline)

        let destinationContext = registry.context(for: destinationRoot)
        #expect(destinationContext.repositoryIdentityState.isConflicted)
        let destinationRegistration =
            IOSAcceptedHistoryCoordinatorRepositoryRegistration(
                registry: registry,
                context: destinationContext,
                applicationSupportDirectoryURL: destinationRoot
            )
        let destinationFixture = CoordinatorFixture(
            repositoryIdentityState:
                destinationContext.repositoryIdentityState,
            repositoryRegistration: destinationRegistration
        )
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await destinationFixture.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(destinationFixture.policy.loadCount == 0)
        #expect(destinationFixture.accepted.loadCount == 0)
        #expect(destinationFixture.outbox.loadCount == 0)
        #expect(destinationFixture.delivery.loadCount == 0)
    }

    @Test func everyMissingAndEmptyOwnerCombinationCreatesPhysicalBaseline() async throws {
        for mask in 0..<8 {
            let fixture = CoordinatorFixture()
            if mask & 1 != 0 {
                fixture.accepted.install(
                    try IOSAcceptedHistoryEnvelope(revision: 1, entries: [])
                )
            }
            if mask & 2 != 0 {
                fixture.outbox.install(
                    try IOSAcceptedHistoryOutboxEnvelope(
                        revision: 1,
                        entries: []
                    )
                )
            }
            if mask & 4 != 0 {
                fixture.delivery.install(
                    try coordinatorDeliveryRecord(historyWrite: nil)
                )
            }

            let capture = try await fixture.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: "en",
                durationMilliseconds: 10
            )

            #expect(fixture.policy.currentState == .baseline)
            #expect(fixture.policy.createCount == 1)
            #expect(capture.historyWrite?.state == .pending)
            #expect(capture.historyWrite?.policyGeneration == 1)
            #expect(fixture.accepted.loadCount == 1)
            #expect(fixture.outbox.loadCount == 1)
            #expect(fixture.delivery.loadCount == 1)
        }
    }

    @Test func eachOccupiedOwnerBlocksPolicyCreation() async throws {
        let accepted = CoordinatorFixture()
        accepted.accepted.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 1,
                entries: [try coordinatorHistoryEntry()]
            )
        )
        await #expect(throws: IOSAcceptedHistoryError.compareAndSwapFailed) {
            _ = try await accepted.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(accepted.policy.createCount == 0)

        let outbox = CoordinatorFixture()
        outbox.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [try coordinatorOutboxEntry()]
            )
        )
        await #expect(throws: IOSAcceptedHistoryOutboxError.compareAndSwapFailed) {
            _ = try await outbox.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(outbox.policy.createCount == 0)

        let delivery = CoordinatorFixture()
        delivery.delivery.install(
            try coordinatorDeliveryRecord(
                historyWrite: IOSAcceptedOutputHistoryWrite(
                    policyGeneration: 1,
                    transcriptionModel: "model",
                    transcriptionLanguageCode: nil,
                    durationMilliseconds: nil
                )
            )
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await delivery.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(delivery.policy.createCount == 0)
    }

    @Test func existingPolicyBypassesOwnerProbesAndConfirmsIdentically() async throws {
        let fixture = CoordinatorFixture()
        let existing = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: false,
            policyGeneration: 2
        )
        fixture.policy.install(existing)

        let capture = try await fixture.coordinator().capture(
            transcriptionModel: "model",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 1
        )

        #expect(fixture.policy.currentState == existing)
        #expect(capture.historyWrite == nil)
        #expect(fixture.accepted.loadCount == 0)
        #expect(fixture.outbox.loadCount == 0)
        #expect(fixture.delivery.loadCount == 0)
        #expect(fixture.policy.replaceCount == 1)
    }

    @Test func firstCaptureCreatesOneOneAndNextMutationCreatesTwoTwo() async throws {
        let fixture = CoordinatorFixture()
        let capture = try await fixture.coordinator().capture(
            transcriptionModel: "model",
            transcriptionLanguageCode: nil,
            durationMilliseconds: nil
        )
        let mutationStore = IOSHistoryPolicyStore(journal: fixture.policy)
        let confirmed = try await mutationStore.confirm(
            expected: IOSHistoryPolicyExpectation(state: .baseline)
        )
        let cleared = try await mutationStore.clear(
            using: confirmed
        )

        #expect(capture.historyWrite?.policyGeneration == 1)
        #expect(cleared.state.revision == 2)
        #expect(cleared.state.policyGeneration == 2)
        #expect(cleared.state.historyEnabled)
    }

    @Test func visibleAndInvisibleBaselineUncertaintyAlwaysReprobe() async throws {
        for visible in [true, false] {
            let fixture = CoordinatorFixture()
            let coordinator = fixture.coordinator()
            fixture.policy.failNextCreate(
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )

            await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
                _ = try await coordinator.capture(
                    transcriptionModel: "model",
                    transcriptionLanguageCode: nil,
                    durationMilliseconds: nil
                )
            }
            _ = try await coordinator.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )

            #expect(fixture.policy.currentState == .baseline)
            #expect(fixture.accepted.loadCount == 2)
            #expect(fixture.outbox.loadCount == 2)
            #expect(fixture.delivery.loadCount == 2)
        }
    }

    @Test func queuedCaptureObservesRecoveryStateBeforeItsLeaseRuns() async throws {
        let gateProbe = CoordinatorGateProbe()
        let gate = IOSPersistenceOperationGate { event in
            gateProbe.record(event)
        }
        let fixture = CoordinatorFixture(gate: gate)
        let coordinator = fixture.coordinator()
        let createBlocker = CoordinatorBoundaryBlocker()
        fixture.policy.createBlocker = createBlocker
        fixture.policy.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        let first = Task {
            try await coordinator.capture(
                transcriptionModel: "first",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(createBlocker.waitUntilBlocked())
        let second = Task {
            try await coordinator.capture(
                transcriptionModel: "second",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(gateProbe.waitUntilEnqueued())
        createBlocker.open()

        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            _ = try await first.value
        }
        let recovered = try await second.value
        #expect(recovered.historyWrite?.transcriptionModel == "second")
        #expect(fixture.accepted.loadCount == 2)
        #expect(fixture.outbox.loadCount == 2)
        #expect(fixture.delivery.loadCount == 2)
    }

    @Test func recoveryFlagSurvivesProbeFailureAndClearsOnDefinitiveWinner() async throws {
        let retryFixture = CoordinatorFixture()
        let retryCoordinator = retryFixture.coordinator()
        retryFixture.policy.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            _ = try await retryCoordinator.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        retryFixture.accepted.failNextLoad(with: .readFailed)
        await #expect(throws: IOSAcceptedHistoryError.readFailed) {
            _ = try await retryCoordinator.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        _ = try await retryCoordinator.capture(
            transcriptionModel: "model",
            transcriptionLanguageCode: nil,
            durationMilliseconds: nil
        )
        #expect(retryFixture.accepted.loadCount == 3)
        #expect(retryFixture.outbox.loadCount == 2)

        let winnerFixture = CoordinatorFixture()
        let winnerCoordinator = winnerFixture.coordinator()
        winnerFixture.policy.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            _ = try await winnerCoordinator.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        let winner = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: true,
            policyGeneration: 2
        )
        winnerFixture.policy.install(winner)
        await #expect(throws: IOSHistoryPolicyError.compareAndSwapFailed) {
            _ = try await winnerCoordinator.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        let probeCount = winnerFixture.accepted.loadCount
        _ = try await winnerCoordinator.capture(
            transcriptionModel: "model",
            transcriptionLanguageCode: nil,
            durationMilliseconds: nil
        )
        #expect(winnerFixture.policy.currentState == winner)
        #expect(winnerFixture.accepted.loadCount == probeCount)
    }

    @Test func baselineReplaceCASKeepsRecoveryAndReprobes() async throws {
        let fixture = CoordinatorFixture()
        let coordinator = fixture.coordinator()
        fixture.policy.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )
        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            _ = try await coordinator.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }

        fixture.policy.raceNextReplace(with: .baseline)
        await #expect(throws: IOSHistoryPolicyError.compareAndSwapFailed) {
            _ = try await coordinator.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(fixture.accepted.loadCount == 2)

        let recovered = try await coordinator.capture(
            transcriptionModel: "model",
            transcriptionLanguageCode: nil,
            durationMilliseconds: nil
        )
        #expect(recovered.historyWrite?.policyGeneration == 1)
        #expect(fixture.accepted.loadCount == 3)
        #expect(fixture.outbox.loadCount == 3)
        #expect(fixture.delivery.loadCount == 3)
    }

    @Test func recoveryStateIsIsolatedAcrossRepositories() async throws {
        let sharedGate = IOSPersistenceOperationGate()
        let first = CoordinatorFixture(gate: sharedGate)
        let second = CoordinatorFixture(gate: sharedGate)
        let firstCoordinator = first.coordinator()
        let secondCoordinator = second.coordinator()
        first.policy.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            _ = try await firstCoordinator.capture(
                transcriptionModel: "first",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }

        second.policy.install(
            try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: true,
                policyGeneration: 2
            )
        )
        _ = try await secondCoordinator.capture(
            transcriptionModel: "second",
            transcriptionLanguageCode: nil,
            durationMilliseconds: nil
        )
        #expect(second.accepted.loadCount == 0)

        _ = try await firstCoordinator.capture(
            transcriptionModel: "first",
            transcriptionLanguageCode: nil,
            durationMilliseconds: nil
        )
        #expect(first.accepted.loadCount == 2)
    }

    @Test func twoCoordinatorsSharingAGateNeverInterleavePolicyConfirmation() async throws {
        let gateProbe = CoordinatorGateProbe()
        let gate = IOSPersistenceOperationGate { event in
            gateProbe.record(event)
        }
        let fixture = CoordinatorFixture(gate: gate)
        fixture.policy.install(.baseline)
        let firstCoordinator = fixture.coordinator()
        let secondCoordinator = fixture.coordinator()
        let loadBlocker = CoordinatorBoundaryBlocker()
        fixture.policy.loadBlocker = loadBlocker

        let first = Task {
            try await firstCoordinator.capture(
                transcriptionModel: "first",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(loadBlocker.waitUntilBlocked())
        let second = Task {
            try await secondCoordinator.capture(
                transcriptionModel: "second",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(gateProbe.waitUntilEnqueued())
        #expect(fixture.policy.loadCount == 1)
        loadBlocker.open()

        #expect(try await first.value.historyWrite?.transcriptionModel == "first")
        #expect(try await second.value.historyWrite?.transcriptionModel == "second")
        #expect(gateProbe.grantedCount == 2)
        #expect(gateProbe.releasedCount == 2)
    }

    @Test func cancellationBeforeLeaseDoesNoWorkAndAfterLeaseCannotInterrupt() async throws {
        let gateProbe = CoordinatorGateProbe()
        let gate = IOSPersistenceOperationGate { event in
            gateProbe.record(event)
        }
        let fixture = CoordinatorFixture(gate: gate)
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let loadBlocker = CoordinatorBoundaryBlocker()
        fixture.policy.loadBlocker = loadBlocker

        let active = Task {
            try await coordinator.capture(
                transcriptionModel: "active",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(loadBlocker.waitUntilBlocked())
        let cancelled = Task {
            try await coordinator.capture(
                transcriptionModel: "cancelled",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(gateProbe.waitUntilEnqueued())
        cancelled.cancel()
        active.cancel()
        loadBlocker.open()

        #expect(try await active.value.historyWrite?.transcriptionModel == "active")
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        ) {
            _ = try await cancelled.value
        }
        #expect(fixture.policy.loadCount == 2)
        #expect(fixture.accepted.loadCount == 0)
        #expect(gateProbe.grantedCount == 1)
        #expect(gateProbe.releasedCount == 1)
    }

    @Test func enabledDisabledAndMetadataBoundariesAreExactAndRedacted() async throws {
        let enabled = CoordinatorFixture()
        enabled.policy.install(
            try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: true,
                policyGeneration: 2
            )
        )
        let enabledCoordinator = enabled.coordinator()
        let capture = try await enabledCoordinator.capture(
            transcriptionModel: "  model  ",
            transcriptionLanguageCode: "eng",
            durationMilliseconds: 299_999
        )
        #expect(capture.historyWrite?.state == .pending)
        #expect(capture.historyWrite?.policyGeneration == 2)
        #expect(capture.historyWrite?.transcriptionModel == "model")
        #expect(capture.historyWrite?.transcriptionLanguageCode == "eng")
        #expect(capture.historyWrite?.durationMilliseconds == 299_999)

        let disabled = CoordinatorFixture()
        disabled.policy.install(
            try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: false,
                policyGeneration: 2
            )
        )
        let disabledCapture = try await disabled.coordinator().capture(
            transcriptionModel: String(repeating: "m", count: 256),
            transcriptionLanguageCode: "en",
            durationMilliseconds: 1
        )
        #expect(disabledCapture.historyWrite == nil)
        #expect(disabled.policy.currentState?.historyEnabled == false)

        let readsBefore = enabled.policy.loadCount
        for invalid in [
            ("", Optional<String>.none, Optional<Int64>.none),
            (String(repeating: "m", count: 257), nil, nil),
            ("model", "e", nil),
            ("model", nil, 0),
            ("model", nil, 300_000),
        ] {
            await #expect(throws: IOSAcceptedOutputDeliveryError.invalidPreparation) {
                _ = try await enabledCoordinator.capture(
                    transcriptionModel: invalid.0,
                    transcriptionLanguageCode: invalid.1,
                    durationMilliseconds: invalid.2
                )
            }
        }
        #expect(enabled.policy.loadCount == readsBefore)

        let rendered = String(describing: capture)
            + String(reflecting: capture)
            + String(describing: Mirror(reflecting: capture))
            + String(describing: IOSAcceptedHistoryCoordinatorError.reentrantOperation)
        #expect(rendered.contains("redacted"))
        #expect(!rendered.contains("model"))
    }
}

private final class CoordinatorFixture: @unchecked Sendable {
    let events = CoordinatorEventRecorder()
    let policy: CoordinatorPolicyJournal
    let accepted: CoordinatorAcceptedJournal
    let outbox: CoordinatorOutboxJournal
    let delivery: CoordinatorDeliveryJournal
    let gate: IOSPersistenceOperationGate
    let recoveryState = IOSAcceptedHistoryBaselineRecoveryState()
    let repositoryIdentityState:
        IOSAcceptedHistoryCoordinatorRepositoryIdentityState
    let repositoryRegistration:
        IOSAcceptedHistoryCoordinatorRepositoryRegistration?

    init(
        gate: IOSPersistenceOperationGate = IOSPersistenceOperationGate(),
        repositoryIdentityState:
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState =
                IOSAcceptedHistoryCoordinatorRepositoryIdentityState(),
        repositoryRegistration:
            IOSAcceptedHistoryCoordinatorRepositoryRegistration? = nil
    ) {
        self.gate = gate
        self.repositoryIdentityState = repositoryIdentityState
        self.repositoryRegistration = repositoryRegistration
        policy = CoordinatorPolicyJournal(events: events)
        accepted = CoordinatorAcceptedJournal(events: events)
        outbox = CoordinatorOutboxJournal(events: events)
        delivery = CoordinatorDeliveryJournal(events: events)
    }

    func coordinator() -> IOSAcceptedHistoryCoordinator {
        IOSAcceptedHistoryCoordinator(
            policyStore: IOSHistoryPolicyStore(journal: policy),
            acceptedHistoryStore: IOSAcceptedHistoryStore(journal: accepted),
            outboxStore: IOSAcceptedHistoryOutboxStore(journal: outbox),
            deliveryStore: IOSAcceptedOutputDeliveryStore(journal: delivery),
            operationGate: gate,
            baselineRecoveryState: recoveryState,
            repositoryIdentityState: repositoryIdentityState,
            repositoryRegistration: repositoryRegistration
        )
    }
}

private final class CoordinatorEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []

    var events: [String] { lock.withLock { storedEvents } }

    func append(_ event: String) {
        lock.withLock { storedEvents.append(event) }
    }
}

private final class CoordinatorPolicyJournal:
    IOSHistoryPolicyJournalStoring,
    @unchecked Sendable {
    private struct Failure {
        let error: IOSHistoryPolicyError
        let commitBeforeThrowing: Bool
    }

    private let lock = NSLock()
    private let events: CoordinatorEventRecorder
    private var snapshot: IOSHistoryPolicyJournalSnapshot?
    private var nextRevisionToken: UInt64 = 1
    private var createFailure: Failure?
    private var nextReplaceRaceState: IOSHistoryPolicyState?
    private var storedLoadCount = 0
    private var storedCreateCount = 0
    private var storedReplaceCount = 0
    var loadBlocker: CoordinatorBoundaryBlocker?
    var createBlocker: CoordinatorBoundaryBlocker?

    init(events: CoordinatorEventRecorder) {
        self.events = events
    }

    var currentState: IOSHistoryPolicyState? {
        lock.withLock { snapshot?.state }
    }
    var loadCount: Int { lock.withLock { storedLoadCount } }
    var createCount: Int { lock.withLock { storedCreateCount } }
    var replaceCount: Int { lock.withLock { storedReplaceCount } }

    func install(_ state: IOSHistoryPolicyState) {
        lock.withLock {
            snapshot = IOSHistoryPolicyJournalSnapshot(
                state: state,
                fileRevision: makeRevisionLocked()
            )
        }
    }

    func failNextCreate(
        with error: IOSHistoryPolicyError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            createFailure = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func raceNextReplace(with state: IOSHistoryPolicyState) {
        lock.withLock { nextReplaceRaceState = state }
    }

    func load() throws -> IOSHistoryPolicyJournalSnapshot? {
        let result = lock.withLock { () -> IOSHistoryPolicyJournalSnapshot? in
            storedLoadCount += 1
            events.append("policy.load")
            return snapshot
        }
        loadBlocker?.blockOnce()
        return result
    }

    func create(
        _ state: IOSHistoryPolicyState,
        authorization: IOSHistoryPolicyBaselineAuthorization
    ) throws -> IOSHistoryPolicyJournalSnapshot {
        _ = authorization
        let result: Result<IOSHistoryPolicyJournalSnapshot, IOSHistoryPolicyError>
        lock.lock()
        storedCreateCount += 1
        events.append("policy.create")
        if snapshot != nil {
            result = .failure(.slotOccupied)
        } else if let failure = createFailure {
            createFailure = nil
            if failure.commitBeforeThrowing {
                snapshot = makeSnapshotLocked(state)
            }
            result = .failure(failure.error)
        } else {
            let created = makeSnapshotLocked(state)
            snapshot = created
            result = .success(created)
        }
        lock.unlock()
        createBlocker?.blockOnce()
        return try result.get()
    }

    func replace(
        _ state: IOSHistoryPolicyState,
        expected: IOSHistoryPolicyJournalSnapshot
    ) throws -> IOSHistoryPolicyJournalSnapshot {
        try lock.withLock {
            storedReplaceCount += 1
            events.append("policy.replace")
            if let raceState = nextReplaceRaceState {
                snapshot = makeSnapshotLocked(raceState)
                nextReplaceRaceState = nil
            }
            guard snapshot == expected else {
                throw IOSHistoryPolicyError.compareAndSwapFailed
            }
            let replacement = makeSnapshotLocked(state)
            snapshot = replacement
            return replacement
        }
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport { .empty }

    private func makeSnapshotLocked(
        _ state: IOSHistoryPolicyState
    ) -> IOSHistoryPolicyJournalSnapshot {
        defer { nextRevisionToken += 1 }
        return IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: nextRevisionToken
            )
        )
    }

    private func makeRevisionLocked() -> IOSStrictProtectedRecordFileRevision {
        defer { nextRevisionToken += 1 }
        return IOSStrictProtectedRecordFileRevision(
            testingToken: nextRevisionToken
        )
    }
}

private final class CoordinatorAcceptedJournal:
    IOSAcceptedHistoryJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private let events: CoordinatorEventRecorder
    private var snapshot: IOSAcceptedHistoryJournalSnapshot?
    private var nextRevisionToken: UInt64 = 1
    private var loadFailure: IOSAcceptedHistoryError?
    private var storedLoadCount = 0

    init(events: CoordinatorEventRecorder) { self.events = events }

    var loadCount: Int { lock.withLock { storedLoadCount } }

    func install(_ envelope: IOSAcceptedHistoryEnvelope) {
        lock.withLock {
            snapshot = IOSAcceptedHistoryJournalSnapshot(
                envelope: envelope,
                fileRevision: revisionLocked()
            )
        }
    }

    func failNextLoad(with error: IOSAcceptedHistoryError) {
        lock.withLock { loadFailure = error }
    }

    func load() throws -> IOSAcceptedHistoryJournalSnapshot? {
        try lock.withLock {
            storedLoadCount += 1
            events.append("accepted.load")
            if let loadFailure {
                self.loadFailure = nil
                throw loadFailure
            }
            return snapshot
        }
    }

    func create(
        _ envelope: IOSAcceptedHistoryEnvelope,
        authorization: IOSAcceptedHistoryJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryJournalSnapshot {
        throw IOSAcceptedHistoryError.writeFailed
    }

    func replace(
        _ envelope: IOSAcceptedHistoryEnvelope,
        expected: IOSAcceptedHistoryJournalSnapshot,
        authorization: IOSAcceptedHistoryJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryJournalSnapshot {
        throw IOSAcceptedHistoryError.writeFailed
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport { .empty }

    private func revisionLocked() -> IOSStrictProtectedRecordFileRevision {
        defer { nextRevisionToken += 1 }
        return IOSStrictProtectedRecordFileRevision(
            testingToken: nextRevisionToken
        )
    }
}

private final class CoordinatorOutboxJournal:
    IOSAcceptedHistoryOutboxJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private let events: CoordinatorEventRecorder
    private var snapshot: IOSAcceptedHistoryOutboxJournalSnapshot?
    private var nextRevisionToken: UInt64 = 1
    private var storedLoadCount = 0

    init(events: CoordinatorEventRecorder) { self.events = events }
    var loadCount: Int { lock.withLock { storedLoadCount } }

    func install(_ envelope: IOSAcceptedHistoryOutboxEnvelope) {
        lock.withLock {
            snapshot = IOSAcceptedHistoryOutboxJournalSnapshot(
                envelope: envelope,
                fileRevision: revisionLocked()
            )
        }
    }

    func load() throws -> IOSAcceptedHistoryOutboxJournalSnapshot? {
        lock.withLock {
            storedLoadCount += 1
            events.append("outbox.load")
            return snapshot
        }
    }

    func create(
        _ envelope: IOSAcceptedHistoryOutboxEnvelope,
        authorization: IOSAcceptedHistoryOutboxJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryOutboxJournalSnapshot {
        throw IOSAcceptedHistoryOutboxError.writeFailed
    }

    func replace(
        _ envelope: IOSAcceptedHistoryOutboxEnvelope,
        expected: IOSAcceptedHistoryOutboxJournalSnapshot,
        authorization: IOSAcceptedHistoryOutboxJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryOutboxJournalSnapshot {
        throw IOSAcceptedHistoryOutboxError.writeFailed
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport { .empty }

    private func revisionLocked() -> IOSStrictProtectedRecordFileRevision {
        defer { nextRevisionToken += 1 }
        return IOSStrictProtectedRecordFileRevision(
            testingToken: nextRevisionToken
        )
    }
}

private final class CoordinatorDeliveryJournal:
    IOSAcceptedOutputDeliveryJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private let events: CoordinatorEventRecorder
    private var snapshot: IOSAcceptedOutputDeliveryJournalSnapshot?
    private var nextRevisionToken: UInt64 = 1
    private var storedLoadCount = 0

    init(events: CoordinatorEventRecorder) { self.events = events }
    var loadCount: Int { lock.withLock { storedLoadCount } }

    func install(_ record: IOSAcceptedOutputDeliveryRecord) {
        lock.withLock {
            snapshot = IOSAcceptedOutputDeliveryJournalSnapshot(
                record: record,
                fileRevision: revisionLocked()
            )
        }
    }

    func load() throws -> IOSAcceptedOutputDeliveryJournalSnapshot? {
        lock.withLock {
            storedLoadCount += 1
            events.append("delivery.load")
            return snapshot
        }
    }

    func loadOpaque() throws -> IOSAcceptedOutputDeliveryOpaqueSnapshot? { nil }

    func create(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        throw IOSAcceptedOutputDeliveryError.writeFailed
    }

    func replace(
        _ record: IOSAcceptedOutputDeliveryRecord,
        expected: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        throw IOSAcceptedOutputDeliveryError.writeFailed
    }

    func remove(expected: IOSAcceptedOutputDeliveryJournalSnapshot) throws {
        throw IOSAcceptedOutputDeliveryError.removeFailed
    }

    func removeOpaque(expected: IOSAcceptedOutputDeliveryOpaqueSnapshot) throws {
        throw IOSAcceptedOutputDeliveryError.removeFailed
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport { .empty }

    private func revisionLocked() -> IOSStrictProtectedRecordFileRevision {
        defer { nextRevisionToken += 1 }
        return IOSStrictProtectedRecordFileRevision(
            testingToken: nextRevisionToken
        )
    }
}

private final class CoordinatorBoundaryBlocker: @unchecked Sendable {
    private let lock = NSLock()
    private let blocked = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)
    private var didBlock = false

    func blockOnce() {
        let shouldBlock = lock.withLock {
            guard !didBlock else { return false }
            didBlock = true
            return true
        }
        guard shouldBlock else { return }
        blocked.signal()
        _ = releaseSignal.wait(timeout: .now() + 10)
    }

    func waitUntilBlocked() -> Bool {
        blocked.wait(timeout: .now() + 10) == .success
    }

    func open() {
        releaseSignal.signal()
    }
}

private final class CoordinatorGateProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let enqueued = DispatchSemaphore(value: 0)
    private var storedGrantedCount = 0
    private var storedReleasedCount = 0

    var grantedCount: Int { lock.withLock { storedGrantedCount } }
    var releasedCount: Int { lock.withLock { storedReleasedCount } }

    func record(_ event: IOSPersistenceOperationGate.Event) {
        switch event {
        case .enqueued:
            enqueued.signal()
        case .granted:
            lock.withLock { storedGrantedCount += 1 }
        case .released:
            lock.withLock { storedReleasedCount += 1 }
        case .installing, .claiming, .cancelled:
            break
        }
    }

    func waitUntilEnqueued() -> Bool {
        enqueued.wait(timeout: .now() + 10) == .success
    }
}

private func coordinatorHistoryEntry() throws -> IOSAcceptedHistoryEntry {
    try IOSAcceptedHistoryEntry(
        deliveryID: UUID(),
        transcriptID: UUID(),
        acceptedText: "accepted",
        outputIntent: .standard,
        createdAt: coordinatorDate(),
        policyGeneration: 1,
        transcriptionModel: "model",
        transcriptionLanguageCode: nil,
        durationMilliseconds: nil,
        cachedAudioRelativeIdentifier: nil
    )
}

private func coordinatorOutboxEntry() throws -> IOSAcceptedHistoryOutboxEntry {
    try IOSAcceptedHistoryOutboxEntry(
        deliveryID: UUID(),
        transcriptID: UUID(),
        acceptedText: "accepted",
        outputIntent: .standard,
        createdAt: coordinatorDate(),
        expiresAt: coordinatorDate().addingTimeInterval(86_400),
        policyGeneration: 1,
        transcriptionModel: "model",
        transcriptionLanguageCode: nil,
        durationMilliseconds: nil
    )
}

private func coordinatorDeliveryRecord(
    historyWrite: IOSAcceptedOutputHistoryWrite?
) throws -> IOSAcceptedOutputDeliveryRecord {
    let date = coordinatorDate()
    return try IOSAcceptedOutputDeliveryRecord(
        revision: 1,
        deliveryID: UUID(),
        sessionID: UUID(),
        attemptID: UUID(),
        transcriptID: UUID(),
        acceptedText: "accepted",
        outputIntent: .standard,
        createdAt: date,
        updatedAt: date,
        expiresAt: date.addingTimeInterval(86_400),
        deliveryState: .pending,
        automaticInsertionPreferenceEnabled: true,
        keepLatestResult: true,
        publicationGeneration: 0,
        historyWrite: historyWrite
    )
}

private func coordinatorDate() -> Date {
    Date(timeIntervalSince1970: 1_800_000_000)
}

private struct CoordinatorFileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}

private func coordinatorFileIdentity(_ url: URL) -> CoordinatorFileIdentity? {
    var status = stat()
    let didRead = url.withUnsafeFileSystemRepresentation { path in
        guard let path else { return false }
        return Darwin.lstat(path, &status) == 0
    }
    guard didRead else { return nil }
    return CoordinatorFileIdentity(
        device: status.st_dev,
        inode: status.st_ino
    )
}
