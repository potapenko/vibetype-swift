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
        #expect(first.failedHistoryStore === sameRoot.failedHistoryStore)
        #expect(first.outboxStore === sameRoot.outboxStore)
        #expect(first.deliveryStore === sameRoot.deliveryStore)
        #expect(
            first.deliveryStore.outboxStoreIdentity
                == first.outboxStore.storeIdentity
        )
        #expect(first.baselineRecoveryState === sameRoot.baselineRecoveryState)
        #expect(first.acceptanceState === sameRoot.acceptanceState)
        #expect(
            first.pendingReplacementState
                === sameRoot.pendingReplacementState
        )
        #expect(first.outboxWorkerState === sameRoot.outboxWorkerState)
        #expect(first.policyCutoverState === sameRoot.policyCutoverState)
        #expect(first.ownerIdentity == sameRoot.ownerIdentity)
        #expect(first !== differentRoot)
        #expect(first.ownerIdentity != differentRoot.ownerIdentity)
        #expect(
            first.failedHistoryStore.capabilityOwnerIdentity
                == first.ownerIdentity
        )
        let renderedBinding = String(describing: binding)
            + String(reflecting: binding)
            + String(describing: Mirror(reflecting: binding))
        #expect(renderedBinding.contains("redacted"))
        #expect(!renderedBinding.contains(parent.path))
        #expect(
            first.baselineRecoveryState
                !== differentRoot.baselineRecoveryState
        )
        #expect(
            first.policyCutoverState
                !== differentRoot.policyCutoverState
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
        let mutationStore = IOSHistoryPolicyStore(
            journal: fixture.policy,
            capabilityOwnerIdentity: fixture.ownerIdentity
        )
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

    @Test func normalAcceptanceCommitsInRequiredOrderAndReturnsRecord() async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(using: coordinator)
        let eventStart = fixture.events.events.count

        let result = try await coordinator.accept(preparation)

        #expect(result.resolution == .committed)
        #expect(result.deliveryRecord.historyWrite?.state == .committed)
        #expect(fixture.delivery.currentRecord == result.deliveryRecord)
        #expect(fixture.accepted.currentEnvelope?.entries.count == 1)
        #expect(
            Array(fixture.events.events.dropFirst(eventStart)) == [
                "delivery.load",
                "delivery.create",
                "delivery.load",
                "delivery.replace",
                "policy.load",
                "policy.replace",
                "accepted.load",
                "accepted.create",
                "policy.load",
                "policy.replace",
                "delivery.load",
                "delivery.replace",
            ]
        )
        let rendered = String(describing: result)
            + String(reflecting: result)
            + String(describing: result.resolution)
            + String(
                describing: IOSAcceptedOutputDeliveryAcceptance(
                    record: result.deliveryRecord,
                    provenance: .freshCurrentProcess
                )
            )
            + String(
                reflecting:
                    IOSAcceptedOutputDeliveryAcceptanceProvenance.preexisting
            )
        #expect(rendered.contains("redacted"))
        #expect(!rendered.contains(preparation.acceptedText))
    }

    @Test func disabledCaptureReturnsNotRequestedWithoutHistoryIO() async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(
            try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: false,
                policyGeneration: 2
            )
        )
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(using: coordinator)

        let result = try await coordinator.accept(preparation)

        #expect(result.resolution == .notRequested)
        #expect(result.deliveryRecord.historyWrite == nil)
        #expect(fixture.accepted.loadCount == 0)
        #expect(fixture.accepted.createCount == 0)
        #expect(fixture.delivery.replaceCount == 0)
    }

    @Test func ownerMismatchAndRawPreparationFailBeforeDeliveryIO() async throws {
        let first = CoordinatorFixture()
        first.policy.install(.baseline)
        let firstCoordinator = first.coordinator()
        let captured = try await coordinatorPreparation(using: firstCoordinator)
        let second = CoordinatorFixture()
        second.policy.install(.baseline)
        let secondCoordinator = second.coordinator()

        await #expect(throws: IOSAcceptedOutputDeliveryError.invalidPreparation) {
            _ = try await secondCoordinator.accept(captured)
        }
        #expect(second.delivery.loadCount == 0)
        #expect(second.delivery.createCount == 0)

        let raw = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "raw",
            outputIntent: .standard,
            automaticInsertionPreferenceEnabled: true,
            keepLatestResult: true,
            historyWrite: captured.historyWrite
        )
        await #expect(throws: IOSAcceptedOutputDeliveryError.invalidPreparation) {
            _ = try await firstCoordinator.accept(raw)
        }
        #expect(first.delivery.loadCount == 0)
        #expect(first.delivery.createCount == 0)
    }

    @Test func mixedCapabilityOwnerCoordinatorIsPoisonedBeforeAnyStoreIO()
        async throws {
        let first = CoordinatorFixture()
        first.policy.install(
            try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: false,
                policyGeneration: 2
            )
        )
        let validCoordinator = first.coordinator()
        let disabledPreparation = try await coordinatorPreparation(
            using: validCoordinator
        )
        let second = CoordinatorFixture()
        let identityState =
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState()
        let mixed = IOSAcceptedHistoryCoordinator(
            policyStore: first.policyStore,
            acceptedHistoryStore: first.acceptedHistoryStore,
            failedHistoryStore: first.failedHistoryStore,
            outboxStore: first.outboxStore,
            deliveryStore: second.deliveryStore,
            operationGate: IOSPersistenceOperationGate(),
            acceptanceState: IOSAcceptedHistoryAcceptanceOperationState(),
            ownerIdentity: first.ownerIdentity,
            repositoryIdentityState: identityState
        )
        let policyLoads = first.policy.loadCount
        let acceptedLoads = first.accepted.loadCount
        let outboxLoads = first.outbox.loadCount
        let deliveryLoads = second.delivery.loadCount

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await mixed.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await mixed.accept(disabledPreparation)
        }
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await mixed.recoverAcceptedHistory()
        }

        #expect(identityState.isConflicted)
        #expect(first.policy.loadCount == policyLoads)
        #expect(first.accepted.loadCount == acceptedLoads)
        #expect(first.outbox.loadCount == outboxLoads)
        #expect(second.delivery.loadCount == deliveryLoads)
        #expect(second.delivery.createCount == 0)
    }

    @Test func foreignFailedHistoryStorePoisonsCoordinatorBeforeAnyStoreIO()
        async throws {
        let first = CoordinatorFixture()
        let second = CoordinatorFixture()
        let identityState =
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState()
        let mixed = IOSAcceptedHistoryCoordinator(
            policyStore: first.policyStore,
            acceptedHistoryStore: first.acceptedHistoryStore,
            failedHistoryStore: second.failedHistoryStore,
            outboxStore: first.outboxStore,
            deliveryStore: first.deliveryStore,
            operationGate: IOSPersistenceOperationGate(),
            acceptanceState: IOSAcceptedHistoryAcceptanceOperationState(),
            ownerIdentity: first.ownerIdentity,
            repositoryIdentityState: identityState
        )
        let policyLoads = first.policy.loadCount
        let acceptedLoads = first.accepted.loadCount
        let outboxLoads = first.outbox.loadCount
        let deliveryLoads = first.delivery.loadCount
        let failedEvents = second.failedHistoryFileSystem.events

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await mixed.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }

        #expect(identityState.isConflicted)
        #expect(first.policy.loadCount == policyLoads)
        #expect(first.accepted.loadCount == acceptedLoads)
        #expect(first.outbox.loadCount == outboxLoads)
        #expect(first.delivery.loadCount == deliveryLoads)
        #expect(second.failedHistoryFileSystem.events == failedEvents)
    }

    @Test func mixedGuardedBaselineEvidenceCannotComposeAuthority()
        async throws {
        let first = CoordinatorFixture()
        let second = CoordinatorFixture()
        let accepted = try await first.acceptedHistoryStore
            .proveGuardedBaseline()
        let outbox = try await second.outboxStore.proveGuardedBaseline()
        let delivery = try await first.deliveryStore.proveGuardedBaseline()
        let failedHistory = try await first.failedHistoryStore
            .proveGuardedBaseline()
        let firstAcceptedLoads = first.accepted.loadCount
        let secondOutboxLoads = second.outbox.loadCount
        let firstDeliveryLoads = first.delivery.loadCount

        #expect(throws: IOSHistoryPolicyError.compareAndSwapFailed) {
            _ = try IOSHistoryPolicyBaselineAuthorization(
                acceptedHistory: accepted,
                outbox: outbox,
                delivery: delivery,
                failedHistory: failedHistory
            )
        }

        #expect(first.accepted.loadCount == firstAcceptedLoads)
        #expect(second.outbox.loadCount == secondOutboxLoads)
        #expect(first.delivery.loadCount == firstDeliveryLoads)
    }

    @Test func guardedBaselineRejectsNonemptyFailedHistoryBeforePolicyCreate()
        async throws {
        let fixture = CoordinatorFixture()
        let envelope = try IOSFailedHistoryEnvelope(
            revision: 1,
            entries: [try failedHistoryTestEntry()],
            audioCleanup: []
        )
        fixture.failedHistoryFileSystem.install(
            try IOSFailedHistoryWireCodec.encode(envelope)
        )

        await #expect(throws: IOSFailedHistoryError.compareAndSwapFailed) {
            _ = try await fixture.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(fixture.policy.createCount == 0)
        #expect(
            try IOSFailedHistoryWireCodec.decode(
                fixture.failedHistoryFileSystem.file!.data
            ) == envelope
        )
    }

    @Test func foreignFailedHistoryBaselineEvidenceCannotComposeAuthority()
        async throws {
        let first = CoordinatorFixture()
        let second = CoordinatorFixture()
        let accepted = try await first.acceptedHistoryStore
            .proveGuardedBaseline()
        let outbox = try await first.outboxStore.proveGuardedBaseline()
        let delivery = try await first.deliveryStore.proveGuardedBaseline()
        let failedHistory = try await second.failedHistoryStore
            .proveGuardedBaseline()

        #expect(throws: IOSHistoryPolicyError.compareAndSwapFailed) {
            _ = try IOSHistoryPolicyBaselineAuthorization(
                acceptedHistory: accepted,
                outbox: outbox,
                delivery: delivery,
                failedHistory: failedHistory
            )
        }
    }

    @Test func mismatchedDeliveryStoreIdentityPoisonsCoordinatorBeforeIO()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let foreignDeliveryJournal = CoordinatorDeliveryJournal(
            events: fixture.events
        )
        let mismatchedDeliveryStore = IOSAcceptedOutputDeliveryStore(
            journal: foreignDeliveryJournal,
            now: { [clock = fixture.clock] in clock.now },
            monotonicNowNanoseconds: {
                [clock = fixture.clock] in clock.uptimeNanoseconds
            },
            capabilityOwnerIdentity: fixture.ownerIdentity
        )
        let identityState =
            IOSAcceptedHistoryCoordinatorRepositoryIdentityState()
        let coordinator = IOSAcceptedHistoryCoordinator(
            policyStore: fixture.policyStore,
            acceptedHistoryStore: fixture.acceptedHistoryStore,
            failedHistoryStore: fixture.failedHistoryStore,
            outboxStore: fixture.outboxStore,
            deliveryStore: mismatchedDeliveryStore,
            operationGate: IOSPersistenceOperationGate(),
            ownerIdentity: fixture.ownerIdentity,
            repositoryIdentityState: identityState
        )
        let counts = (
            fixture.policy.loadCount,
            fixture.accepted.loadCount,
            fixture.outbox.loadCount,
            foreignDeliveryJournal.loadCount
        )

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await coordinator.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(identityState.isConflicted)
        #expect(fixture.policy.loadCount == counts.0)
        #expect(fixture.accepted.loadCount == counts.1)
        #expect(fixture.outbox.loadCount == counts.2)
        #expect(foreignDeliveryJournal.loadCount == counts.3)
    }

    @Test func deliveryFailureBeforeBoundaryRemainsTypedAndRetryable() async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(using: coordinator)
        fixture.delivery.failNextCreate(
            with: .writeFailed,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.writeFailed) {
            _ = try await coordinator.accept(preparation)
        }
        #expect(fixture.accepted.loadCount == 0)

        let retried = try await coordinator.accept(preparation)
        #expect(retried.resolution == .committed)
        #expect(fixture.delivery.createCount == 2)
    }

    @Test func rowUncertaintyResumesExactPhaseAcrossCoordinators() async throws {
        for visible in [false, true] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let first = fixture.coordinator()
            let preparation = try await coordinatorPreparation(using: first)
            fixture.accepted.failNextCreate(
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )

            let pending = try await first.accept(preparation)
            #expect(pending.resolution == .pendingLocalRecovery)
            #expect(fixture.delivery.createCount == 1)
            #expect(fixture.delivery.replaceCount == 1)

            let recovered = try await fixture.coordinator().accept(preparation)
            #expect(recovered.resolution == .committed)
            #expect(fixture.delivery.createCount == 1)
            #expect(fixture.delivery.replaceCount == 2)
            #expect(fixture.accepted.currentEnvelope?.entries.count == 1)
        }
    }

    @Test func policyAndMarkerUncertaintyRetainExactPostDeliveryPhase() async throws {
        for visible in [false, true] {
            let policyFixture = CoordinatorFixture()
            policyFixture.policy.install(.baseline)
            let policyCoordinator = policyFixture.coordinator()
            let policyPreparation = try await coordinatorPreparation(
                using: policyCoordinator
            )
            let failingPolicyCall = policyFixture.policy.replaceCount + 2
            policyFixture.policy.failReplace(
                onCall: failingPolicyCall,
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )

            let policyPending = try await policyCoordinator.accept(
                policyPreparation
            )
            #expect(policyPending.resolution == .pendingLocalRecovery)
            #expect(policyFixture.accepted.createCount == 1)
            #expect(policyFixture.delivery.replaceCount == 1)
            let policyRecovered = try await policyFixture.coordinator().accept(
                policyPreparation
            )
            #expect(policyRecovered.resolution == .committed)
            #expect(policyFixture.accepted.createCount == 1)
            #expect(policyFixture.delivery.createCount == 1)
            #expect(policyFixture.delivery.replaceCount == 2)

            let markerFixture = CoordinatorFixture()
            markerFixture.policy.install(.baseline)
            let markerCoordinator = markerFixture.coordinator()
            let markerPreparation = try await coordinatorPreparation(
                using: markerCoordinator
            )
            markerFixture.delivery.failReplace(
                onCall: markerFixture.delivery.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )

            let markerPending = try await markerCoordinator.accept(
                markerPreparation
            )
            #expect(markerPending.resolution == .pendingLocalRecovery)
            let policyCount = markerFixture.policy.replaceCount
            let acceptedCount = markerFixture.accepted.createCount
            let markerRecovered = try await markerFixture.coordinator().accept(
                markerPreparation
            )
            #expect(markerRecovered.resolution == .committed)
            #expect(markerFixture.policy.replaceCount == policyCount)
            #expect(markerFixture.accepted.createCount == acceptedCount)
            #expect(markerFixture.delivery.createCount == 1)
            #expect(markerFixture.delivery.replaceCount == 3)
        }
    }

    @Test func policyCutoverCancelsBeforeOrAfterRowDecision() async throws {
        let before = CoordinatorFixture()
        before.policy.install(.baseline)
        let beforeCoordinator = before.coordinator()
        let beforePreparation = try await coordinatorPreparation(
            using: beforeCoordinator
        )
        let disabled = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: false,
            policyGeneration: 2
        )
        before.policy.raceNextReplace(with: disabled)

        let cancelledBefore = try await beforeCoordinator.accept(
            beforePreparation
        )
        #expect(cancelledBefore.resolution == .cancelled)
        #expect(cancelledBefore.deliveryRecord.historyWrite?.state == .cancelled)
        #expect(before.accepted.createCount == 0)

        let after = CoordinatorFixture()
        after.policy.install(.baseline)
        let afterCoordinator = after.coordinator()
        let afterPreparation = try await coordinatorPreparation(
            using: afterCoordinator
        )
        after.policy.raceReplace(
            onCall: after.policy.replaceCount + 2,
            with: disabled
        )

        let cancelledAfter = try await afterCoordinator.accept(afterPreparation)
        #expect(cancelledAfter.resolution == .cancelled)
        #expect(cancelledAfter.deliveryRecord.historyWrite?.state == .cancelled)
        #expect(after.accepted.createCount == 1)
        #expect(after.accepted.currentEnvelope?.entries.count == 1)
    }

    @Test func providerFreeRelaunchConfirmsMembershipButNeverInserts() async throws {
        let present = CoordinatorFixture()
        present.policy.install(.baseline)
        let presentCoordinator = present.coordinator()
        let presentPreparation = try await coordinatorPreparation(
            using: presentCoordinator
        )
        present.delivery.failReplace(
            onCall: present.delivery.replaceCount + 2,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(
            try await presentCoordinator.accept(presentPreparation).resolution
                == .pendingLocalRecovery
        )
        #expect(present.accepted.currentEnvelope?.entries.count == 1)

        let recovered = try await present.relaunchedCoordinator()
            .recoverAcceptedHistory()
        #expect(recovered == .committed)
        #expect(present.delivery.currentRecord?.historyWrite?.state == .committed)

        let absent = CoordinatorFixture()
        absent.policy.install(.baseline)
        let absentCoordinator = absent.coordinator()
        let absentPreparation = try await coordinatorPreparation(
            using: absentCoordinator
        )
        absent.accepted.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(
            try await absentCoordinator.accept(absentPreparation).resolution
                == .pendingLocalRecovery
        )
        let createCount = absent.accepted.createCount
        let relaunched = absent.relaunchedCoordinator()
        #expect(
            try await relaunched.recoverAcceptedHistory()
                == .pendingLocalRecovery
        )
        #expect(absent.accepted.createCount == createCount)
        #expect(absent.accepted.currentEnvelope == nil)
        #expect(absent.delivery.currentRecord?.historyWrite?.state == .pending)
    }

    @Test func committedMarkerIsTerminalEvenWhenRowIsAbsent() async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(using: coordinator)
        #expect(
            try await coordinator.accept(preparation).resolution == .committed
        )
        fixture.accepted.install(
            try IOSAcceptedHistoryEnvelope(revision: 2, entries: [])
        )
        let acceptedLoads = fixture.accepted.loadCount

        let recovered = try await fixture.relaunchedCoordinator()
            .recoverAcceptedHistory()

        #expect(recovered == .committed)
        #expect(fixture.accepted.loadCount == acceptedLoads)
        #expect(fixture.accepted.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func expiryAbandonsWithoutRowWorkAndRollbackMutatesNothing() async throws {
        let expired = CoordinatorFixture()
        expired.policy.install(.baseline)
        let expiredCoordinator = expired.coordinator()
        let expiredPreparation = try await coordinatorPreparation(
            using: expiredCoordinator
        )
        expired.accepted.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(
            try await expiredCoordinator.accept(expiredPreparation).resolution
                == .pendingLocalRecovery
        )
        let acceptedLoads = expired.accepted.loadCount
        let markerReplaces = expired.delivery.replaceCount
        expired.clock.advance(seconds: 86_400)

        #expect(
            try await expired.relaunchedCoordinator().recoverAcceptedHistory()
                == nil
        )
        #expect(expired.delivery.currentRecord == nil)
        #expect(expired.delivery.removeCount == 1)
        #expect(expired.accepted.loadCount == acceptedLoads)
        #expect(expired.delivery.replaceCount == markerReplaces + 1)

        let rollback = CoordinatorFixture()
        rollback.policy.install(.baseline)
        let rollbackCoordinator = rollback.coordinator()
        let rollbackPreparation = try await coordinatorPreparation(
            using: rollbackCoordinator
        )
        rollback.accepted.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(
            try await rollbackCoordinator.accept(rollbackPreparation).resolution
                == .pendingLocalRecovery
        )
        let rollbackAcceptedLoads = rollback.accepted.loadCount
        let rollbackDeliveryReplaces = rollback.delivery.replaceCount
        rollback.clock.rollBack(seconds: 1)

        #expect(
            try await rollback.relaunchedCoordinator()
                .recoverAcceptedHistory() == .pendingLocalRecovery
        )
        #expect(rollback.accepted.loadCount == rollbackAcceptedLoads)
        #expect(rollback.delivery.replaceCount == rollbackDeliveryReplaces)
        #expect(rollback.delivery.removeCount == 0)
        #expect(rollback.delivery.currentRecord?.historyWrite?.state == .pending)
    }

    @Test func expiredRemovalFailureStaysPendingAndDifferentWorkCannotClobberPhase()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let first = try await coordinatorPreparation(
            using: coordinator,
            text: "first"
        )
        fixture.accepted.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(
            try await coordinator.accept(first).resolution
                == .pendingLocalRecovery
        )
        let second = try await coordinatorPreparation(
            using: coordinator,
            text: "second"
        )
        let deliveryLoads = fixture.delivery.loadCount
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await fixture.coordinator().accept(second)
        }
        #expect(fixture.delivery.loadCount == deliveryLoads)

        fixture.clock.advance(seconds: 86_400)
        fixture.delivery.failNextRemove(with: .removeFailed)
        #expect(
            try await fixture.relaunchedCoordinator().recoverAcceptedHistory()
                == .pendingLocalRecovery
        )
        #expect(fixture.delivery.currentRecord != nil)
    }

    @Test func rebuiltAcceptanceAfterProcessLossCannotResurrectAbsentRow()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let originalCoordinator = fixture.coordinator()
        let original = try await coordinatorPreparation(
            using: originalCoordinator
        )
        fixture.accepted.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(
            try await originalCoordinator.accept(original).resolution
                == .pendingLocalRecovery
        )
        let rowCreates = fixture.accepted.createCount
        let rowReplaces = fixture.accepted.replaceCount

        let relaunched = fixture.relaunchedCoordinator()
        let rebuilt = try await rebuiltPreparation(
            using: relaunched,
            matching: original
        )
        let result = try await relaunched.accept(rebuilt)

        #expect(result.resolution == .pendingLocalRecovery)
        #expect(fixture.accepted.createCount == rowCreates)
        #expect(fixture.accepted.replaceCount == rowReplaces)
        #expect(fixture.accepted.currentEnvelope == nil)
        #expect(fixture.delivery.currentRecord?.historyWrite?.state == .pending)
        #expect(
            try await relaunched.accept(rebuilt).resolution
                == .pendingLocalRecovery
        )
        #expect(fixture.accepted.createCount == rowCreates)
        #expect(fixture.accepted.replaceCount == rowReplaces)
    }

    @Test func acceptanceProvenanceSurvivesVisibleAndInvisibleUncertainty()
        async throws {
        for visible in [false, true] {
            let fresh = CoordinatorFixture()
            fresh.policy.install(.baseline)
            let freshCoordinator = fresh.coordinator()
            let freshPreparation = try await coordinatorPreparation(
                using: freshCoordinator
            )
            fresh.delivery.failNextCreate(
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                _ = try await freshCoordinator.accept(freshPreparation)
            }
            #expect(
                try await freshCoordinator.accept(freshPreparation).resolution
                    == .committed
            )
            #expect(fresh.accepted.currentEnvelope?.entries.count == 1)

            let preexisting = CoordinatorFixture()
            preexisting.policy.install(.baseline)
            let originalCoordinator = preexisting.coordinator()
            let original = try await coordinatorPreparation(
                using: originalCoordinator
            )
            preexisting.accepted.failNextCreate(
                with: .commitUncertain,
                commitBeforeThrowing: false
            )
            #expect(
                try await originalCoordinator.accept(original).resolution
                    == .pendingLocalRecovery
            )
            let relaunched = preexisting.relaunchedCoordinator()
            let rebuilt = try await rebuiltPreparation(
                using: relaunched,
                matching: original
            )
            preexisting.delivery.failReplace(
                onCall: preexisting.delivery.replaceCount + 1,
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                _ = try await relaunched.accept(rebuilt)
            }
            let rowCreates = preexisting.accepted.createCount
            #expect(
                try await relaunched.accept(rebuilt).resolution
                    == .pendingLocalRecovery
            )
            #expect(preexisting.accepted.createCount == rowCreates)
            #expect(preexisting.accepted.currentEnvelope == nil)
        }
    }

    @Test func retainedUncertaintyReconcilesBeforeExpiryOrRollbackBranch()
        async throws {
        for visible in [false, true] {
            let row = CoordinatorFixture()
            row.policy.install(.baseline)
            let rowCoordinator = row.coordinator()
            let rowPreparation = try await coordinatorPreparation(
                using: rowCoordinator
            )
            row.accepted.failNextCreate(
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )
            #expect(
                try await rowCoordinator.accept(rowPreparation).resolution
                    == .pendingLocalRecovery
            )
            row.clock.advance(seconds: 86_400)
            #expect(try await rowCoordinator.recoverAcceptedHistory() == nil)
            #expect(row.delivery.currentRecord == nil)
            #expect(row.delivery.removeCount == 1)
            #expect(row.accepted.currentEnvelope?.entries.count == (visible ? 1 : nil))

            let marker = CoordinatorFixture()
            marker.policy.install(.baseline)
            let markerCoordinator = marker.coordinator()
            let markerPreparation = try await coordinatorPreparation(
                using: markerCoordinator
            )
            marker.delivery.failReplace(
                onCall: marker.delivery.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )
            #expect(
                try await markerCoordinator.accept(markerPreparation).resolution
                    == .pendingLocalRecovery
            )
            marker.clock.advance(seconds: 86_400)
            let markerRecovery = try await markerCoordinator
                .recoverAcceptedHistory()
            #expect(markerRecovery == (visible ? .committed : nil))
            #expect(
                marker.delivery.currentRecord?.historyWrite?.state
                    == (visible ? .committed : nil)
            )

            let rollback = CoordinatorFixture()
            rollback.policy.install(.baseline)
            let rollbackCoordinator = rollback.coordinator()
            let rollbackPreparation = try await coordinatorPreparation(
                using: rollbackCoordinator
            )
            rollback.delivery.failReplace(
                onCall: rollback.delivery.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )
            #expect(
                try await rollbackCoordinator.accept(rollbackPreparation)
                    .resolution == .pendingLocalRecovery
            )
            rollback.clock.rollBack(seconds: 1)
            let rollbackRecovery = try await rollbackCoordinator
                .recoverAcceptedHistory()
            #expect(
                rollbackRecovery
                    == (visible ? .committed : .pendingLocalRecovery)
            )
            #expect(rollback.delivery.removeCount == 0)
        }
    }

    @Test func relaunchThatExpiresDuringConfirmationAbandonsInSameCall()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let original = fixture.coordinator()
        let preparation = try await coordinatorPreparation(using: original)
        fixture.accepted.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(
            try await original.accept(preparation).resolution
                == .pendingLocalRecovery
        )

        fixture.clock.advanceOnRead(3, seconds: 86_400)
        let resolution = try await fixture.relaunchedCoordinator()
            .recoverAcceptedHistory()

        #expect(resolution == nil)
        #expect(fixture.delivery.currentRecord == nil)
        #expect(fixture.delivery.removeCount == 1)
    }

    @Test func retainedAbandonmentReloadsANewerDeliveryBeforeReturning()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(using: coordinator)
        fixture.accepted.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(
            try await coordinator.accept(preparation).resolution
                == .pendingLocalRecovery
        )
        fixture.clock.advance(seconds: 86_400)
        #expect(
            try await coordinator.accept(preparation).resolution
                == .pendingLocalRecovery
        )
        #expect(fixture.delivery.currentRecord == nil)

        let newer = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "newer",
            outputIntent: .standard,
            automaticInsertionPreferenceEnabled: true,
            keepLatestResult: true,
            historyWrite: nil
        )
        _ = try await fixture.deliveryStore.accept(newer)

        #expect(
            try await coordinator.recoverAcceptedHistory() == .notRequested
        )
        #expect(fixture.delivery.currentRecord?.deliveryID == newer.deliveryID)
    }

    @Test func relaunchTerminalMatrixAlwaysUsesGenericIdenticalRewrite()
        async throws {
        let noMarker = CoordinatorFixture()
        noMarker.policy.install(.baseline)
        let raw = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "no marker",
            outputIntent: .standard,
            automaticInsertionPreferenceEnabled: true,
            keepLatestResult: true,
            historyWrite: nil
        )
        _ = try await noMarker.deliveryStore.accept(raw)
        let noMarkerReplaces = noMarker.delivery.replaceCount
        #expect(
            try await noMarker.relaunchedCoordinator()
                .recoverAcceptedHistory() == .notRequested
        )
        #expect(noMarker.delivery.replaceCount == noMarkerReplaces + 1)

        let committed = CoordinatorFixture()
        committed.policy.install(.baseline)
        let committedCoordinator = committed.coordinator()
        let committedPreparation = try await coordinatorPreparation(
            using: committedCoordinator
        )
        #expect(
            try await committedCoordinator.accept(committedPreparation)
                .resolution == .committed
        )
        let committedReplaces = committed.delivery.replaceCount
        #expect(
            try await committed.relaunchedCoordinator()
                .recoverAcceptedHistory() == .committed
        )
        #expect(committed.delivery.replaceCount == committedReplaces + 1)

        let cancelled = CoordinatorFixture()
        cancelled.policy.install(.baseline)
        let cancelledCoordinator = cancelled.coordinator()
        let cancelledPreparation = try await coordinatorPreparation(
            using: cancelledCoordinator
        )
        cancelled.policy.raceNextReplace(
            with: try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: false,
                policyGeneration: 2
            )
        )
        #expect(
            try await cancelledCoordinator.accept(cancelledPreparation)
                .resolution == .cancelled
        )
        let cancelledReplaces = cancelled.delivery.replaceCount
        #expect(
            try await cancelled.relaunchedCoordinator()
                .recoverAcceptedHistory() == .cancelled
        )
        #expect(cancelled.delivery.replaceCount == cancelledReplaces + 1)
    }

    @Test func repeatedGenericConfirmationUncertaintyStaysPendingThenRecovers()
        async throws {
        for visible in [false, true] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let raw = try IOSAcceptedOutputDeliveryPreparation(
                deliveryID: UUID(),
                sessionID: UUID(),
                attemptID: UUID(),
                transcriptID: UUID(),
                rawAcceptedText: "terminal",
                outputIntent: .standard,
                automaticInsertionPreferenceEnabled: true,
                keepLatestResult: true,
                historyWrite: nil
            )
            _ = try await fixture.deliveryStore.accept(raw)
            let firstFailure = fixture.delivery.replaceCount + 1
            fixture.delivery.failReplace(
                onCall: firstFailure,
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )
            fixture.delivery.failReplace(
                onCall: firstFailure + 1,
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )
            let relaunched = fixture.relaunchedCoordinator()

            #expect(
                try await relaunched.recoverAcceptedHistory()
                    == .pendingLocalRecovery
            )
            #expect(
                try await relaunched.recoverAcceptedHistory()
                    == .pendingLocalRecovery
            )
            #expect(
                try await relaunched.recoverAcceptedHistory() == .notRequested
            )
            #expect(fixture.accepted.loadCount == 0)
        }
    }

    @Test func cancellationUncertaintyRetriesExactInvalidationPhase()
        async throws {
        for visible in [false, true] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let coordinator = fixture.coordinator()
            let preparation = try await coordinatorPreparation(
                using: coordinator
            )
            fixture.policy.raceNextReplace(
                with: try IOSHistoryPolicyState(
                    revision: 2,
                    historyEnabled: false,
                    policyGeneration: 2
                )
            )
            fixture.delivery.failReplace(
                onCall: fixture.delivery.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )

            #expect(
                try await coordinator.accept(preparation).resolution
                    == .pendingLocalRecovery
            )
            let policyReplaces = fixture.policy.replaceCount
            let acceptedLoads = fixture.accepted.loadCount
            #expect(
                try await fixture.coordinator().accept(preparation).resolution
                    == .cancelled
            )
            #expect(fixture.policy.replaceCount == policyReplaces)
            #expect(fixture.accepted.loadCount == acceptedLoads)
            #expect(fixture.accepted.createCount == 0)
            #expect(fixture.delivery.createCount == 1)
            #expect(fixture.delivery.replaceCount == 3)
            #expect(
                try await fixture.relaunchedCoordinator()
                    .recoverAcceptedHistory() == .cancelled
            )
            #expect(fixture.delivery.replaceCount == 4)
        }
    }

    @Test func expiryObservationSurvivesConfirmationUncertaintyAndRollback()
        async throws {
        for visible in [false, true] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let coordinator = fixture.coordinator()
            let preparation = try await coordinatorPreparation(
                using: coordinator
            )
            fixture.delivery.failReplace(
                onCall: fixture.delivery.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: false
            )
            #expect(
                try await coordinator.accept(preparation).resolution
                    == .pendingLocalRecovery
            )
            fixture.clock.advance(seconds: 86_400)
            fixture.delivery.failReplace(
                onCall: fixture.delivery.replaceCount + 1,
                with: .commitUncertain,
                commitBeforeThrowing: visible
            )

            #expect(
                try await coordinator.recoverAcceptedHistory()
                    == .pendingLocalRecovery
            )
            let acceptedLoads = fixture.accepted.loadCount
            let policyReplaces = fixture.policy.replaceCount
            fixture.clock.rollBack(seconds: 86_401)

            #expect(try await coordinator.recoverAcceptedHistory() == nil)
            #expect(fixture.delivery.currentRecord == nil)
            #expect(fixture.delivery.removeCount == 1)
            #expect(fixture.accepted.loadCount == acceptedLoads)
            #expect(fixture.policy.replaceCount == policyReplaces)
        }
    }

    @Test func expiryRemovalCapabilitiesAreOpaqueAndRedacted() async throws {
        let fixture = CoordinatorFixture()
        let preparation = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "EXPIRY-CAPABILITY-SECRET",
            outputIntent: .standard,
            automaticInsertionPreferenceEnabled: true,
            keepLatestResult: true,
            historyWrite: nil
        )
        let record = try await fixture.deliveryStore.accept(preparation)
        fixture.clock.advance(seconds: 86_400)
        let observedResult = try await fixture.deliveryStore
            .observeExpiredHistoryAbandonment(
                expected: IOSAcceptedOutputDeliveryExpectation(record: record)
            )
        guard case .observed(let observation) = observedResult else {
            Issue.record("Expected sealed expiry observation")
            return
        }
        let removalResult = try await fixture.deliveryStore
            .confirmExpiredHistoryAbandonment(observation: observation)
        guard case .authorized(let authorization) = removalResult else {
            Issue.record("Expected sealed expiry removal authorization")
            return
        }

        let rendered = String(describing: observedResult)
            + String(reflecting: observation)
            + String(describing: removalResult)
            + String(reflecting: authorization)
        #expect(rendered.contains("redacted"))
        #expect(!rendered.contains("EXPIRY-CAPABILITY-SECRET"))
    }

    @Test func expiryCapabilitiesCannotCrossDeliveryStoreRoots() async throws {
        let first = CoordinatorFixture()
        let second = CoordinatorFixture()
        let preparation = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "CROSS-ROOT-EXPIRY-SECRET",
            outputIntent: .standard,
            automaticInsertionPreferenceEnabled: true,
            keepLatestResult: true,
            historyWrite: nil
        )
        let record = try await first.deliveryStore.accept(preparation)
        second.delivery.install(record)
        first.clock.advance(seconds: 86_400)
        second.clock.advance(seconds: 86_400)
        let observedResult = try await first.deliveryStore
            .observeExpiredHistoryAbandonment(
                expected: IOSAcceptedOutputDeliveryExpectation(record: record)
            )
        guard case .observed(let observation) = observedResult else {
            Issue.record("Expected first-store expiry observation")
            return
        }

        let secondLoadsBeforeConfirmation = second.delivery.loadCount
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await second.deliveryStore
                .confirmExpiredHistoryAbandonment(observation: observation)
        }
        #expect(second.delivery.loadCount == secondLoadsBeforeConfirmation)
        #expect(second.delivery.currentRecord == record)

        let removalResult = try await first.deliveryStore
            .confirmExpiredHistoryAbandonment(observation: observation)
        guard case .authorized(let authorization) = removalResult else {
            Issue.record("Expected first-store removal authorization")
            return
        }
        let secondLoadsBeforeRemoval = second.delivery.loadCount
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.compareAndSwapFailed
        ) {
            _ = try await second.deliveryStore
                .continueExpiredHistoryAbandonment(
                    authorization: authorization
                )
        }
        #expect(second.delivery.loadCount == secondLoadsBeforeRemoval)
        #expect(second.delivery.currentRecord == record)

        let rendered = String(reflecting: observation)
            + String(reflecting: authorization)
        #expect(rendered.contains("redacted"))
        #expect(!rendered.contains("CROSS-ROOT-EXPIRY-SECRET"))
    }

    @Test func authorizedExpiryRemovalNeverReturnsToHistoryWork()
        async throws {
        for mode in 0..<4 {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let coordinator = fixture.coordinator()
            let preparation = try await coordinatorPreparation(
                using: coordinator
            )
            fixture.delivery.failReplace(
                onCall: fixture.delivery.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: false
            )
            #expect(
                try await coordinator.accept(preparation).resolution
                    == .pendingLocalRecovery
            )
            fixture.clock.advance(seconds: 86_400)
            let removalError: IOSAcceptedOutputDeliveryError =
                mode == 0 ? .removeFailed : .removalCommitUncertain
            fixture.delivery.failNextRemove(
                with: removalError,
                commitBeforeThrowing: mode == 2
            )

            #expect(
                try await coordinator.recoverAcceptedHistory()
                    == .pendingLocalRecovery
            )
            let acceptedLoads = fixture.accepted.loadCount
            let policyReplaces = fixture.policy.replaceCount
            let markerState = fixture.delivery.currentRecord?.historyWrite?.state
            let replaces = fixture.delivery.replaceCount
            if mode == 3, let record = fixture.delivery.currentRecord {
                fixture.delivery.install(record)
            }
            fixture.clock.rollBack(seconds: 86_401)

            #expect(try await coordinator.recoverAcceptedHistory() == nil)
            #expect(fixture.delivery.currentRecord == nil)
            #expect(fixture.accepted.loadCount == acceptedLoads)
            #expect(fixture.policy.replaceCount == policyReplaces)
            #expect(markerState == (mode == 2 ? nil : .pending))
            #expect(
                fixture.delivery.replaceCount
                    == replaces + (mode == 3 ? 1 : 0)
            )
        }
    }

    @Test func supersededExpiryRemovalReloadsNewDeliveryWithoutErasingIt()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(using: coordinator)
        fixture.delivery.failReplace(
            onCall: fixture.delivery.replaceCount + 2,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(
            try await coordinator.accept(preparation).resolution
                == .pendingLocalRecovery
        )
        fixture.clock.advance(seconds: 86_400)
        fixture.delivery.failNextRemove(with: .removeFailed)
        #expect(
            try await coordinator.recoverAcceptedHistory()
                == .pendingLocalRecovery
        )

        let newer = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "newer after authorized expiry",
            outputIntent: .standard,
            automaticInsertionPreferenceEnabled: true,
            keepLatestResult: true,
            historyWrite: nil
        )
        _ = try await fixture.deliveryStore.accept(newer)

        #expect(
            try await coordinator.recoverAcceptedHistory() == .notRequested
        )
        #expect(fixture.delivery.currentRecord?.deliveryID == newer.deliveryID)
        #expect(fixture.delivery.currentRecord?.acceptedText == newer.acceptedText)
    }

    @Test func cancellationBeforeAcceptanceLeaseDoesNoAdditionalWork()
        async throws {
        let probe = CoordinatorGateProbe()
        let gate = IOSPersistenceOperationGate { event in probe.record(event) }
        let fixture = CoordinatorFixture(gate: gate)
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(using: coordinator)
        let blocker = CoordinatorBoundaryBlocker()
        fixture.policy.loadBlocker = blocker

        let active = Task { try await coordinator.accept(preparation) }
        #expect(blocker.waitUntilBlocked())
        let cancelled = Task {
            try await fixture.coordinator().accept(preparation)
        }
        #expect(probe.waitUntilEnqueued())
        cancelled.cancel()
        blocker.open()

        #expect(try await active.value.resolution == .committed)
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        ) {
            _ = try await cancelled.value
        }
        #expect(fixture.delivery.createCount == 1)
        #expect(fixture.accepted.createCount == 1)
    }

    @Test func bindingConflictAfterDeliveryBoundaryReturnsPendingNotThrowing()
        async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-accept-binding-\(UUID().uuidString)",
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
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(using: coordinator)
        let blocker = CoordinatorBoundaryBlocker()
        fixture.policy.loadBlocker = blocker
        let acceptance = Task { try await coordinator.accept(preparation) }
        #expect(blocker.waitUntilBlocked())
        #expect(fixture.delivery.currentRecord != nil)
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        blocker.open()

        let result = try await acceptance.value
        #expect(result.resolution == .pendingLocalRecovery)
        #expect(context.repositoryIdentityState.isConflicted)
        #expect(await fixture.acceptanceState.current() != nil)
    }

    @Test func supersededReloadFailureKeepsPostBoundaryBindingSemantics()
        async throws {
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-superseded-binding-\(UUID().uuidString)",
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
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(using: coordinator)
        fixture.delivery.failReplace(
            onCall: fixture.delivery.replaceCount + 2,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(
            try await coordinator.accept(preparation).resolution
                == .pendingLocalRecovery
        )
        fixture.clock.advance(seconds: 86_400)
        fixture.delivery.failNextRemove(with: .removeFailed)
        #expect(
            try await coordinator.recoverAcceptedHistory()
                == .pendingLocalRecovery
        )

        let newer = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "newer retained boundary",
            outputIntent: .standard,
            automaticInsertionPreferenceEnabled: true,
            keepLatestResult: true,
            historyWrite: nil
        )
        _ = try await fixture.deliveryStore.accept(newer)
        let reloadCall = fixture.delivery.loadCount + 2
        let blocker = CoordinatorBoundaryBlocker()
        fixture.delivery.failLoad(onCall: reloadCall, with: .readFailed)
        fixture.delivery.blockLoad(onCall: reloadCall, with: blocker)
        let recovery = Task {
            try await coordinator.recoverAcceptedHistory()
        }
        #expect(blocker.waitUntilBlocked())
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        blocker.open()

        #expect(try await recovery.value == .pendingLocalRecovery)
        #expect(context.repositoryIdentityState.isConflicted)
        #expect(fixture.delivery.currentRecord?.deliveryID == newer.deliveryID)
    }

    @Test func pendingReplacementTransfersOldDeliveryBeforeFreshAcceptance()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let old = try await coordinatorPreparation(
            using: coordinator,
            text: "old accepted text"
        )
        _ = try await fixture.deliveryStore.accept(old)
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "fresh replacement text"
        )
        let eventOffset = fixture.events.events.count

        let result = try await coordinator.accept(replacement)

        #expect(result.resolution == .committed)
        #expect(result.deliveryRecord.deliveryID == replacement.deliveryID)
        #expect(
            fixture.delivery.currentRecord?.deliveryID
                == replacement.deliveryID
        )
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state == .committed
        )
        #expect(fixture.outbox.currentEnvelope?.entries.count == 1)
        #expect(
            fixture.outbox.currentEnvelope?.entries.first?.deliveryID
                == old.deliveryID
        )
        #expect(
            fixture.outbox.currentEnvelope?.entries.first?.acceptedText
                == old.acceptedText
        )
        #expect(
            fixture.accepted.currentEnvelope?.entries.first?.deliveryID
                == replacement.deliveryID
        )
        #expect(await fixture.pendingReplacementState.current() == nil)

        let events = Array(fixture.events.events.dropFirst(eventOffset))
        let outboxIndex = try #require(
            events.firstIndex(of: "outbox.create")
        )
        let replacementIndex = try #require(
            events.indices.first(where: {
                $0 > outboxIndex && events[$0] == "delivery.replace"
            })
        )
        let rowIndex = try #require(
            events.indices.first(where: {
                $0 > replacementIndex && events[$0] == "accepted.create"
            })
        )
        #expect(outboxIndex < replacementIndex)
        #expect(replacementIndex < rowIndex)
    }

    @Test func stalePendingReplacementCancelsOldMarkerWithoutOutbox()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let old = try await coordinatorPreparation(
            using: coordinator,
            text: "stale old text"
        )
        _ = try await fixture.deliveryStore.accept(old)
        fixture.policy.install(
            try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: true,
                policyGeneration: 2
            )
        )
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "current generation text"
        )

        let result = try await coordinator.accept(replacement)

        #expect(result.resolution == .committed)
        #expect(result.deliveryRecord.deliveryID == replacement.deliveryID)
        #expect(result.deliveryRecord.historyWrite?.policyGeneration == 2)
        #expect(fixture.outbox.currentEnvelope == nil)
        #expect(fixture.outbox.createCount == 0)
        #expect(
            fixture.accepted.currentEnvelope?.entries.first?.deliveryID
                == replacement.deliveryID
        )
    }

    @Test func outboxTransferUncertaintyRetainsExactReplacementWork()
        async throws {
        for commitBeforeThrowing in [false, true] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let coordinator = fixture.coordinator()
            let old = try await coordinatorPreparation(
                using: coordinator,
                text: "old uncertain transfer"
            )
            _ = try await fixture.deliveryStore.accept(old)
            let replacement = try await coordinatorPreparation(
                using: coordinator,
                text: "new uncertain transfer"
            )
            let different = try await coordinatorPreparation(
                using: coordinator,
                text: "must not steal transfer"
            )
            fixture.outbox.failNextCreate(
                with: .commitUncertain,
                commitBeforeThrowing: commitBeforeThrowing
            )

            await #expect(
                throws: IOSAcceptedHistoryOutboxError.commitUncertain
            ) {
                _ = try await coordinator.accept(replacement)
            }
            let deliveryLoads = fixture.delivery.loadCount
            let policyLoads = fixture.policy.loadCount
            let outboxLoads = fixture.outbox.loadCount
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                _ = try await fixture.coordinator().accept(different)
            }
            #expect(fixture.delivery.loadCount == deliveryLoads)
            #expect(fixture.policy.loadCount == policyLoads)
            #expect(fixture.outbox.loadCount == outboxLoads)

            let result = try await fixture.coordinator().accept(replacement)
            #expect(result.resolution == .committed)
            #expect(result.deliveryRecord.deliveryID == replacement.deliveryID)
            #expect(fixture.outbox.currentEnvelope?.entries.count == 1)
            #expect(
                fixture.outbox.currentEnvelope?.entries.first?.deliveryID
                    == old.deliveryID
            )
            #expect(await fixture.pendingReplacementState.current() == nil)
        }
    }

    @Test func outboxTransferConfirmationCASRetainsReservedPhase()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let old = try await coordinatorPreparation(
            using: coordinator,
            text: "old visible outbox transfer"
        )
        _ = try await fixture.deliveryStore.accept(old)
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "replacement after outbox confirmation"
        )
        fixture.outbox.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(
            throws: IOSAcceptedHistoryOutboxError.commitUncertain
        ) {
            _ = try await coordinator.accept(replacement)
        }
        let retained = try #require(
            await fixture.pendingReplacementState.current()
        )
        guard case .transferReserved = retained.phase else {
            Issue.record("Expected the exact transfer-reserved phase")
            return
        }
        fixture.outbox.failReplace(
            onCall: fixture.outbox.replaceCount + 1,
            with: .compareAndSwapFailed,
            commitBeforeThrowing: false
        )

        await #expect(
            throws: IOSAcceptedHistoryOutboxError.commitUncertain
        ) {
            _ = try await coordinator.accept(replacement)
        }
        #expect(
            await fixture.pendingReplacementState.current() == retained
        )

        let result = try await coordinator.accept(replacement)
        #expect(result.resolution == .committed)
        #expect(result.deliveryRecord.deliveryID == replacement.deliveryID)
        #expect(
            fixture.outbox.currentEnvelope?.entries.first?.deliveryID
                == old.deliveryID
        )
        #expect(await fixture.pendingReplacementState.current() == nil)
    }

    @Test func deliveryReplacementUncertaintyPreservesFreshProvenance()
        async throws {
        for commitBeforeThrowing in [false, true] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let coordinator = fixture.coordinator()
            let old = try await coordinatorPreparation(
                using: coordinator,
                text: "old replacement uncertainty"
            )
            _ = try await fixture.deliveryStore.accept(old)
            let replacement = try await coordinatorPreparation(
                using: coordinator,
                text: "new replacement uncertainty"
            )
            let different = try await coordinatorPreparation(
                using: coordinator,
                text: "cannot steal replacement"
            )
            fixture.delivery.failReplace(
                onCall: fixture.delivery.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: commitBeforeThrowing
            )

            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                _ = try await coordinator.accept(replacement)
            }
            #expect(fixture.outbox.currentEnvelope?.entries.count == 1)
            let deliveryLoads = fixture.delivery.loadCount
            let policyLoads = fixture.policy.loadCount
            let outboxLoads = fixture.outbox.loadCount
            await #expect(
                throws: IOSAcceptedOutputDeliveryError.commitUncertain
            ) {
                _ = try await fixture.coordinator().accept(different)
            }
            #expect(fixture.delivery.loadCount == deliveryLoads)
            #expect(fixture.policy.loadCount == policyLoads)
            #expect(fixture.outbox.loadCount == outboxLoads)

            let result = try await fixture.coordinator().accept(replacement)
            #expect(result.resolution == .committed)
            #expect(result.deliveryRecord.deliveryID == replacement.deliveryID)
            #expect(
                fixture.accepted.currentEnvelope?.entries.first?.deliveryID
                    == replacement.deliveryID
            )
            #expect(await fixture.pendingReplacementState.current() == nil)
        }
    }

    @Test func pendingReplacementConfirmationCASRetainsTransferredPhase()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let old = try await coordinatorPreparation(
            using: coordinator,
            text: "old visible delivery replacement"
        )
        _ = try await fixture.deliveryStore.accept(old)
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "replacement after delivery confirmation"
        )
        fixture.delivery.failReplace(
            onCall: fixture.delivery.replaceCount + 2,
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.commitUncertain
        ) {
            _ = try await coordinator.accept(replacement)
        }
        let retained = try #require(
            await fixture.pendingReplacementState.current()
        )
        guard case .outboxTransferred = retained.phase else {
            Issue.record("Expected the exact outbox-transferred phase")
            return
        }
        fixture.delivery.failReplace(
            onCall: fixture.delivery.replaceCount + 1,
            with: .compareAndSwapFailed,
            commitBeforeThrowing: false
        )

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.commitUncertain
        ) {
            _ = try await coordinator.accept(replacement)
        }
        #expect(
            await fixture.pendingReplacementState.current() == retained
        )

        let result = try await coordinator.accept(replacement)
        #expect(result.resolution == .committed)
        #expect(result.deliveryRecord.deliveryID == replacement.deliveryID)
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state == .committed
        )
        #expect(await fixture.pendingReplacementState.current() == nil)
    }

    @Test func cancellationConfirmationCASRetainsInvalidationPhase()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let old = try await coordinatorPreparation(
            using: coordinator,
            text: "old visible cancellation"
        )
        _ = try await fixture.deliveryStore.accept(old)
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "replacement after cancellation confirmation"
        )
        fixture.policy.install(
            try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: false,
                policyGeneration: 2
            )
        )
        fixture.delivery.failReplace(
            onCall: fixture.delivery.replaceCount + 2,
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.commitUncertain
        ) {
            _ = try await coordinator.accept(replacement)
        }
        let retained = try #require(
            await fixture.pendingReplacementState.current()
        )
        guard case .invalidationConfirmed = retained.phase else {
            Issue.record("Expected the exact invalidation-confirmed phase")
            return
        }
        fixture.delivery.failReplace(
            onCall: fixture.delivery.replaceCount + 1,
            with: .compareAndSwapFailed,
            commitBeforeThrowing: false
        )

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.commitUncertain
        ) {
            _ = try await coordinator.accept(replacement)
        }
        #expect(
            await fixture.pendingReplacementState.current() == retained
        )

        let result = try await coordinator.accept(replacement)
        #expect(result.resolution == .cancelled)
        #expect(result.deliveryRecord.deliveryID == replacement.deliveryID)
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state == .cancelled
        )
        #expect(await fixture.pendingReplacementState.current() == nil)
    }

    @Test func visibleReplacementSurvivesProcessLossAndReplaysAbsentRow()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let old = try await coordinatorPreparation(
            using: coordinator,
            text: "old before visible replacement"
        )
        _ = try await fixture.deliveryStore.accept(old)
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "replacement visible before process loss"
        )
        fixture.delivery.failReplace(
            onCall: fixture.delivery.replaceCount + 2,
            with: .commitUncertain,
            commitBeforeThrowing: true
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await coordinator.accept(replacement)
        }
        #expect(
            fixture.delivery.currentRecord?.deliveryID
                == replacement.deliveryID
        )
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state
                == .pendingReplacement
        )
        #expect(fixture.accepted.currentEnvelope == nil)
        let rowCreates = fixture.accepted.createCount

        let resolution = try await fixture.relaunchedCoordinator()
            .recoverAcceptedHistory()

        #expect(resolution == .committed)
        #expect(fixture.accepted.createCount == rowCreates + 1)
        #expect(
            fixture.accepted.currentEnvelope?.entries.first?.deliveryID
                == replacement.deliveryID
        )
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state == .committed
        )
    }

    @Test func replacementCapacityLossIsSealedOnlyByTerminalMarker()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let old = try await coordinatorPreparation(
            using: coordinator,
            text: "old before capacity loss"
        )
        _ = try await fixture.deliveryStore.accept(old)

        let createdAt = fixture.clock.now
        let entries = try (0..<20).map { index in
            try IOSAcceptedHistoryEntry(
                deliveryID: #require(
                    UUID(
                        uuidString: String(
                            format:
                                "00000000-0000-0000-0000-%012X",
                            index + 1
                        )
                    )
                ),
                transcriptID: #require(
                    UUID(
                        uuidString: String(
                            format:
                                "10000000-0000-0000-0000-%012X",
                            index + 1
                        )
                    )
                ),
                acceptedText: "newer stable row \(index)",
                outputIntent: .standard,
                createdAt: createdAt,
                policyGeneration: 1,
                transcriptionModel: "whisper-1",
                transcriptionLanguageCode: "en",
                durationMilliseconds: 1_250,
                cachedAudioRelativeIdentifier: nil
            )
        }
        fixture.accepted.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 9,
                entries: IOSAcceptedHistoryValidation.sorted(entries)
            )
        )
        let capture = try await coordinator.capture(
            transcriptionModel: "whisper-1",
            transcriptionLanguageCode: "en",
            durationMilliseconds: 1_250
        )
        let replacementDeliveryID = try #require(
            UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")
        )
        let replacement = try IOSAcceptedOutputDeliveryPreparation(
            deliveryID: replacementDeliveryID,
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            rawAcceptedText: "capacity loser replacement",
            outputIntent: .standard,
            automaticInsertionPreferenceEnabled: true,
            keepLatestResult: true,
            historyCapture: capture
        )
        fixture.delivery.failReplace(
            onCall: fixture.delivery.replaceCount + 4,
            with: .commitUncertain,
            commitBeforeThrowing: true
        )
        let acceptedReplaces = fixture.accepted.replaceCount

        let result = try await coordinator.accept(replacement)

        #expect(result.resolution == .pendingLocalRecovery)
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state == .committed
        )
        #expect(fixture.accepted.replaceCount == acceptedReplaces + 1)
        #expect(
            fixture.accepted.currentEnvelope?.entries
                .contains(where: { $0.deliveryID == replacementDeliveryID })
                == false
        )

        fixture.accepted.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 10,
                entries: Array(
                    IOSAcceptedHistoryValidation.sorted(entries).dropLast()
                )
            )
        )
        let rowWritesBeforeRecovery = (
            fixture.accepted.createCount,
            fixture.accepted.replaceCount
        )

        #expect(
            try await fixture.relaunchedCoordinator()
                .recoverAcceptedHistory() == .committed
        )
        #expect(fixture.accepted.createCount == rowWritesBeforeRecovery.0)
        #expect(fixture.accepted.replaceCount == rowWritesBeforeRecovery.1)
        #expect(
            fixture.accepted.currentEnvelope?.entries
                .contains(where: { $0.deliveryID == replacementDeliveryID })
                == false
        )
    }

    @Test func retainedReplacementBypassesTerminalAndDiscardedOldSlots()
        async throws {
        let variants: [(IOSAcceptedOutputHistoryWriteState?, Bool)] = [
            (.committed, false),
            (.cancelled, false),
            (nil, false),
            (nil, true),
        ]
        for (markerState, discarded) in variants {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let coordinator = fixture.coordinator()
            let old = try await coordinatorPreparation(
                using: coordinator,
                text: "terminal old"
            )
            let accepted = try await fixture.deliveryStore.accept(old)
            let marker = try markerState.map {
                try #require(accepted.historyWrite).replacingState($0)
            }
            fixture.delivery.install(
                try IOSAcceptedOutputDeliveryRecord(
                    revision: accepted.revision + 1,
                    deliveryID: accepted.deliveryID,
                    sessionID: accepted.sessionID,
                    attemptID: accepted.attemptID,
                    transcriptID: accepted.transcriptID,
                    acceptedText: discarded ? nil : accepted.acceptedText,
                    outputIntent: accepted.outputIntent,
                    createdAt: accepted.createdAt,
                    updatedAt: accepted.updatedAt,
                    expiresAt: accepted.expiresAt,
                    deliveryState: discarded ? .discarded : .pending,
                    automaticInsertionPreferenceEnabled: discarded
                        ? false
                        : accepted.automaticInsertionPreferenceEnabled,
                    keepLatestResult: accepted.keepLatestResult,
                    publicationGeneration: 0,
                    historyWrite: discarded ? nil : marker
                )
            )
            let replacement = try await coordinatorPreparation(
                using: coordinator,
                text: "replacement after terminal old"
            )
            await fixture.pendingReplacementState.store(
                IOSAcceptedHistoryPendingReplacementWork(
                    ownerIdentity: fixture.ownerIdentity,
                    preparation: replacement,
                    phase: .observingCurrentDelivery
                )
            )
            let outboxCreates = fixture.outbox.createCount
            let outboxReplaces = fixture.outbox.replaceCount

            let resolution = try await coordinator.recoverAcceptedHistory()

            #expect(resolution == .committed)
            #expect(
                fixture.delivery.currentRecord?.deliveryID
                    == replacement.deliveryID
            )
            #expect(fixture.outbox.createCount == outboxCreates)
            #expect(fixture.outbox.replaceCount == outboxReplaces)
            #expect(await fixture.pendingReplacementState.current() == nil)
        }
    }

    @Test func retainedReplacementRecognizesAlreadyCurrentReplayableDelivery()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "already current replacement"
        )
        let accepted = try await fixture.deliveryStore.accept(replacement)
        let replayableMarker = try #require(accepted.historyWrite)
            .replacingState(.pendingReplacement)
        fixture.delivery.install(
            try IOSAcceptedOutputDeliveryRecord(
                revision: accepted.revision,
                deliveryID: accepted.deliveryID,
                sessionID: accepted.sessionID,
                attemptID: accepted.attemptID,
                transcriptID: accepted.transcriptID,
                acceptedText: accepted.acceptedText,
                outputIntent: accepted.outputIntent,
                createdAt: accepted.createdAt,
                updatedAt: accepted.updatedAt,
                expiresAt: accepted.expiresAt,
                deliveryState: accepted.deliveryState,
                automaticInsertionPreferenceEnabled:
                    accepted.automaticInsertionPreferenceEnabled,
                keepLatestResult: accepted.keepLatestResult,
                publicationGeneration: accepted.publicationGeneration,
                historyWrite: replayableMarker
            )
        )
        await fixture.pendingReplacementState.store(
            IOSAcceptedHistoryPendingReplacementWork(
                ownerIdentity: fixture.ownerIdentity,
                preparation: replacement,
                phase: .observingCurrentDelivery
            )
        )

        #expect(try await coordinator.recoverAcceptedHistory() == .committed)
        #expect(fixture.outbox.currentEnvelope == nil)
        #expect(
            fixture.accepted.currentEnvelope?.entries.first?.deliveryID
                == replacement.deliveryID
        )
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state == .committed
        )
    }

    @Test func foreignRetainedReplacementIsClearedBeforeAnyStoreIO()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(
            using: coordinator,
            text: "foreign retained replacement"
        )
        await fixture.pendingReplacementState.store(
            IOSAcceptedHistoryPendingReplacementWork(
                ownerIdentity: IOSAcceptedHistoryCoordinatorOwnerIdentity(),
                preparation: preparation,
                phase: .observingCurrentDelivery
            )
        )
        let counts = (
            fixture.policy.loadCount,
            fixture.policy.createCount,
            fixture.policy.replaceCount,
            fixture.accepted.loadCount,
            fixture.accepted.createCount,
            fixture.accepted.replaceCount,
            fixture.outbox.loadCount,
            fixture.outbox.createCount,
            fixture.outbox.replaceCount,
            fixture.delivery.loadCount,
            fixture.delivery.createCount,
            fixture.delivery.replaceCount,
            fixture.delivery.removeCount,
            fixture.events.events
        )

        #expect(
            try await coordinator.recoverAcceptedHistory()
                == .pendingLocalRecovery
        )
        #expect(fixture.policy.loadCount == counts.0)
        #expect(fixture.policy.createCount == counts.1)
        #expect(fixture.policy.replaceCount == counts.2)
        #expect(fixture.accepted.loadCount == counts.3)
        #expect(fixture.accepted.createCount == counts.4)
        #expect(fixture.accepted.replaceCount == counts.5)
        #expect(fixture.outbox.loadCount == counts.6)
        #expect(fixture.outbox.createCount == counts.7)
        #expect(fixture.outbox.replaceCount == counts.8)
        #expect(fixture.delivery.loadCount == counts.9)
        #expect(fixture.delivery.createCount == counts.10)
        #expect(fixture.delivery.replaceCount == counts.11)
        #expect(fixture.delivery.removeCount == counts.12)
        #expect(fixture.events.events == counts.13)
        #expect(await fixture.pendingReplacementState.current() == nil)
    }

    @Test func retainedReplacementWorkAndPhaseRedactAcceptedText()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let preparation = try await coordinatorPreparation(
            using: fixture.coordinator(),
            text: "PENDING-REPLACEMENT-WORK-SECRET"
        )
        let phase = IOSAcceptedHistoryPendingReplacementPhase
            .observingCurrentDelivery
        let work = IOSAcceptedHistoryPendingReplacementWork(
            ownerIdentity: fixture.ownerIdentity,
            preparation: preparation,
            phase: phase
        )

        let rendered = String(describing: phase)
            + String(reflecting: phase)
            + String(describing: Mirror(reflecting: phase))
            + String(describing: work)
            + String(reflecting: work)
            + String(describing: Mirror(reflecting: work))
        #expect(rendered.contains("redacted"))
        #expect(!rendered.contains("PENDING-REPLACEMENT-WORK-SECRET"))
        #expect(phase.customMirror.children.isEmpty)
        #expect(work.customMirror.children.isEmpty)
    }

    @Test func foreignRetainedPhaseCapabilitiesFailBeforeAnyStoreIO()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(
            using: coordinator,
            text: "local replacement preparation"
        )

        let foreign = CoordinatorFixture()
        foreign.policy.install(.baseline)
        let foreignCoordinator = foreign.coordinator()
        let foreignOld = try await coordinatorPreparation(
            using: foreignCoordinator,
            text: "foreign pending delivery"
        )
        let foreignRecord = try await foreign.deliveryStore.accept(foreignOld)
        let foreignAuthorization = try await foreign.deliveryStore
            .authorizePendingHistoryWrite(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: foreignRecord
                )
            )
        let foreignState = try #require(try await foreign.policyStore.load())
        let foreignPolicy = try await foreign.policyStore.confirm(
            expected: IOSHistoryPolicyExpectation(state: foreignState)
        )
        let foreignReservation = try await foreign.deliveryStore
            .reservePendingHistoryTransfer(
                authorization: foreignAuthorization,
                policyReceipt: foreignPolicy
            )
        let foreignOutbox = try await foreign.outboxStore.transfer(
            reservation: foreignReservation
        )
        let foreignInvalidState = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: false,
            policyGeneration: 2
        )
        foreign.policy.install(foreignInvalidState)
        let foreignInvalidation = try await foreign.policyStore.confirm(
            expected: IOSHistoryPolicyExpectation(
                state: foreignInvalidState
            )
        )
        let phases: [IOSAcceptedHistoryPendingReplacementPhase] = [
            .deliveryAuthorized(foreignAuthorization),
            .policyConfirmed(foreignAuthorization, foreignPolicy),
            .transferReserved(foreignReservation),
            .outboxTransferred(foreignReservation, foreignOutbox),
            .invalidationConfirmed(
                foreignAuthorization,
                foreignInvalidation
            ),
        ]
        let counts = (
            fixture.policy.loadCount,
            fixture.policy.createCount,
            fixture.policy.replaceCount,
            fixture.accepted.loadCount,
            fixture.accepted.createCount,
            fixture.accepted.replaceCount,
            fixture.outbox.loadCount,
            fixture.outbox.createCount,
            fixture.outbox.replaceCount,
            fixture.delivery.loadCount,
            fixture.delivery.createCount,
            fixture.delivery.replaceCount,
            fixture.delivery.removeCount,
            fixture.events.events
        )

        for phase in phases {
            await fixture.pendingReplacementState.store(
                IOSAcceptedHistoryPendingReplacementWork(
                    ownerIdentity: fixture.ownerIdentity,
                    preparation: preparation,
                    phase: phase
                )
            )
            #expect(
                try await coordinator.recoverAcceptedHistory()
                    == .pendingLocalRecovery
            )
            #expect(await fixture.pendingReplacementState.current() == nil)
        }

        #expect(fixture.policy.loadCount == counts.0)
        #expect(fixture.policy.createCount == counts.1)
        #expect(fixture.policy.replaceCount == counts.2)
        #expect(fixture.accepted.loadCount == counts.3)
        #expect(fixture.accepted.createCount == counts.4)
        #expect(fixture.accepted.replaceCount == counts.5)
        #expect(fixture.outbox.loadCount == counts.6)
        #expect(fixture.outbox.createCount == counts.7)
        #expect(fixture.outbox.replaceCount == counts.8)
        #expect(fixture.delivery.loadCount == counts.9)
        #expect(fixture.delivery.createCount == counts.10)
        #expect(fixture.delivery.replaceCount == counts.11)
        #expect(fixture.delivery.removeCount == counts.12)
        #expect(fixture.events.events == counts.13)
    }

    @Test func expiryDuringInvisibleTransferUsesAtomicDeliveryReplacement()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let old = try await coordinatorPreparation(
            using: coordinator,
            text: "old expiring transfer"
        )
        _ = try await fixture.deliveryStore.accept(old)
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "replacement after expiry"
        )
        fixture.outbox.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.commitUncertain
        ) {
            _ = try await coordinator.accept(replacement)
        }

        fixture.clock.advance(seconds: 86_400)
        let result = try await fixture.coordinator().accept(replacement)

        #expect(result.resolution == .committed)
        #expect(result.deliveryRecord.deliveryID == replacement.deliveryID)
        #expect(fixture.delivery.createCount == 1)
        #expect(fixture.delivery.removeCount == 0)
        #expect(fixture.outbox.currentEnvelope == nil)
        #expect(
            fixture.accepted.currentEnvelope?.entries.first?.deliveryID
                == replacement.deliveryID
        )
    }

    @Test func providerFreeRecoveryFinishesRetainedPendingReplacement()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let old = try await coordinatorPreparation(
            using: coordinator,
            text: "old retained for recovery"
        )
        _ = try await fixture.deliveryStore.accept(old)
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "provider-free replacement"
        )
        fixture.outbox.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.commitUncertain
        ) {
            _ = try await coordinator.accept(replacement)
        }

        let resolution = try await fixture.coordinator()
            .recoverAcceptedHistory()

        #expect(resolution == .committed)
        #expect(
            fixture.delivery.currentRecord?.deliveryID
                == replacement.deliveryID
        )
        #expect(
            fixture.accepted.currentEnvelope?.entries.first?.deliveryID
                == replacement.deliveryID
        )
        #expect(await fixture.pendingReplacementState.current() == nil)
    }

    @Test func processLossRefreshesOutboxProofBeforeFreshReplacement()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let old = try await coordinatorPreparation(
            using: coordinator,
            text: "old process-loss transfer"
        )
        _ = try await fixture.deliveryStore.accept(old)
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "new process-loss transfer"
        )
        fixture.delivery.failReplace(
            onCall: fixture.delivery.replaceCount + 2,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.commitUncertain
        ) {
            _ = try await coordinator.accept(replacement)
        }
        #expect(fixture.outbox.currentEnvelope?.revision == 1)
        #expect(
            fixture.delivery.currentRecord?.deliveryID == old.deliveryID
        )

        let relaunched = fixture.relaunchedCoordinator()
        let rebuilt = try await rebuiltPreparation(
            using: relaunched,
            matching: replacement
        )
        let result = try await relaunched.accept(rebuilt)

        #expect(result.resolution == .committed)
        #expect(result.deliveryRecord.deliveryID == replacement.deliveryID)
        #expect(fixture.outbox.currentEnvelope?.revision == 1)
        #expect(fixture.outbox.replaceCount >= 1)
        #expect(
            fixture.accepted.currentEnvelope?.entries.first?.deliveryID
                == replacement.deliveryID
        )
    }

    @Test func captureCannotRewritePolicyDuringRetainedReplacementPhase()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let old = try await coordinatorPreparation(using: coordinator)
        _ = try await fixture.deliveryStore.accept(old)
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "retained replacement"
        )
        fixture.outbox.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(
            throws: IOSAcceptedHistoryOutboxError.commitUncertain
        ) {
            _ = try await coordinator.accept(replacement)
        }
        let policyLoads = fixture.policy.loadCount
        let policyReplaces = fixture.policy.replaceCount

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.commitUncertain
        ) {
            _ = try await fixture.coordinator().capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(fixture.policy.loadCount == policyLoads)
        #expect(fixture.policy.replaceCount == policyReplaces)
    }
}

@Suite(.serialized)
struct IOSAcceptedHistoryOutboxWorkerTests {
    @Test func repositoryConflictAfterHeadObservationStaysTyped()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let head = try coordinatorOutboxEntry(
            index: 0,
            createdAt: fixture.clock.now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [head]
            )
        )
        let blocker = CoordinatorBoundaryBlocker()
        fixture.policy.loadBlocker = blocker
        let coordinator = fixture.coordinator()
        let recovery = Task {
            try await coordinator.recoverAcceptedHistoryOutbox()
        }

        #expect(blocker.waitUntilBlocked())
        #expect(await fixture.outboxWorkerState.current() != nil)
        fixture.repositoryIdentityState.markConflicted()
        blocker.open()

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await recovery.value
        }
        let loads = (
            fixture.policy.loadCount,
            fixture.accepted.loadCount,
            fixture.outbox.loadCount,
            fixture.delivery.loadCount
        )
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await coordinator.recoverAcceptedHistoryOutbox()
        }
        #expect(fixture.policy.loadCount == loads.0)
        #expect(fixture.accepted.loadCount == loads.1)
        #expect(fixture.outbox.loadCount == loads.2)
        #expect(fixture.delivery.loadCount == loads.3)
    }

    @Test func cancellationBeforeWorkerLeaseDoesNoRepositoryWork()
        async throws {
        let probe = CoordinatorGateProbe()
        let gate = IOSPersistenceOperationGate { event in probe.record(event) }
        let fixture = CoordinatorFixture(gate: gate)
        fixture.policy.install(.baseline)
        let head = try coordinatorOutboxEntry(
            index: 1,
            createdAt: fixture.clock.now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [head]
            )
        )
        let blocker = CoordinatorAsyncOperationBlocker()
        let active = Task {
            try await gate.perform { await blocker.wait() }
        }
        await blocker.waitUntilSuspended()
        let coordinator = fixture.coordinator()
        let cancelled = Task {
            try await coordinator.recoverAcceptedHistoryOutbox()
        }
        #expect(probe.waitUntilEnqueued())
        cancelled.cancel()
        await blocker.open()

        try await active.value
        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.cancelledBeforeOperation
        ) {
            _ = try await cancelled.value
        }
        #expect(fixture.policy.loadCount == 0)
        #expect(fixture.accepted.loadCount == 0)
        #expect(fixture.outbox.loadCount == 0)
        #expect(fixture.delivery.loadCount == 0)
        #expect(await fixture.outboxWorkerState.current() == nil)
    }

    @Test func reentrantWorkerCallFailsBeforeRepositoryWork() async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()

        await #expect(
            throws: IOSAcceptedHistoryCoordinatorError.reentrantOperation
        ) {
            _ = try await fixture.gate.perform {
                try await coordinator.recoverAcceptedHistoryOutbox()
            }
        }
        #expect(fixture.policy.loadCount == 0)
        #expect(fixture.accepted.loadCount == 0)
        #expect(fixture.outbox.loadCount == 0)
        #expect(fixture.delivery.loadCount == 0)
        #expect(await fixture.outboxWorkerState.current() == nil)
    }

    @Test func foreignGatePrebindingPoisonsCoordinatorBeforeRepositoryIO()
        async throws {
        for (bindsOutbox, bindsDelivery) in [
            (true, false),
            (false, true),
            (true, true),
        ] {
            let fixture = CoordinatorFixture()
            let foreignGate = IOSPersistenceOperationGate()
            if bindsOutbox {
                #expect(
                    fixture.outboxStore.bindOperationGateIdentity(
                        foreignGate.identity
                    )
                )
                #expect(
                    !fixture.outboxStore.bindOperationGateIdentity(
                        fixture.gate.identity
                    )
                )
            }
            if bindsDelivery {
                #expect(
                    fixture.deliveryStore.bindOperationGateIdentity(
                        foreignGate.identity
                    )
                )
                #expect(
                    !fixture.deliveryStore.bindOperationGateIdentity(
                        fixture.gate.identity
                    )
                )
            }

            let coordinator = fixture.coordinator()
            await #expect(
                throws: IOSAcceptedHistoryCoordinatorError
                    .repositoryIdentityConflict
            ) {
                _ = try await coordinator.recoverAcceptedHistoryOutbox()
            }
            #expect(fixture.events.events.isEmpty)
            #expect(fixture.policy.loadCount == 0)
            #expect(fixture.accepted.loadCount == 0)
            #expect(fixture.outbox.loadCount == 0)
            #expect(fixture.delivery.loadCount == 0)
            #expect(await fixture.outboxWorkerState.current() == nil)
        }
    }

    @Test func terminalDeliveryReplacementRequiresExactOutboxAbsence()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "new accepted result"
        )
        let prior = try coordinatorOutboxEntry(
            index: 1,
            createdAt: fixture.clock.now.addingTimeInterval(-10),
            acceptedText: "sealed prior result"
        )
        fixture.delivery.install(
            try coordinatorDeliveryRecord(
                matching: prior,
                state: .committed
            )
        )

        let result = try await coordinator.accept(replacement)

        #expect(result.resolution == .committed)
        #expect(result.deliveryRecord.deliveryID == replacement.deliveryID)
        #expect(fixture.delivery.currentRecord?.deliveryID == replacement.deliveryID)
        #expect(
            fixture.accepted.currentEnvelope?.entries.first?.deliveryID
                == replacement.deliveryID
        )
        #expect(fixture.outbox.currentEnvelope == nil)
    }

    @Test func terminalDeliveryWithMatchingOutboxBlocksUntilWorkerRetiresHead()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let replacement = try await coordinatorPreparation(
            using: coordinator,
            text: "new accepted result"
        )
        let prior = try coordinatorOutboxEntry(
            index: 2,
            createdAt: fixture.clock.now.addingTimeInterval(-10),
            acceptedText: "sealed prior result"
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [prior]
            )
        )
        fixture.delivery.install(
            try coordinatorDeliveryRecord(
                matching: prior,
                state: .committed
            )
        )

        await #expect(
            throws: IOSAcceptedOutputDeliveryError.historyTransferRequired
        ) {
            _ = try await coordinator.accept(replacement)
        }
        #expect(fixture.delivery.currentRecord?.deliveryID == prior.deliveryID)
        #expect(fixture.outbox.currentEnvelope?.entries == [prior])
        #expect(await fixture.pendingReplacementState.current() == nil)

        #expect(
            try await coordinator.recoverAcceptedHistoryOutbox() == .retired
        )
        let result = try await coordinator.accept(replacement)

        #expect(result.resolution == .committed)
        #expect(result.deliveryRecord.deliveryID == replacement.deliveryID)
        #expect(fixture.outbox.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func retainedInitialAcceptanceUncertaintyPreventsWorkerLease()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(
            using: coordinator,
            text: "uncertain accepted result"
        )
        let head = try coordinatorOutboxEntry(
            index: 3,
            createdAt: fixture.clock.now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [head]
            )
        )
        fixture.delivery.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await coordinator.accept(preparation)
        }
        let outboxLoads = fixture.outbox.loadCount

        #expect(
            try await coordinator.recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        #expect(fixture.outbox.loadCount == outboxLoads)
        #expect(await fixture.outboxWorkerState.current() == nil)

        let result = try await coordinator.accept(preparation)
        #expect(result.resolution == .committed)
        #expect(result.deliveryRecord.deliveryID == preparation.deliveryID)
        #expect(fixture.outbox.currentEnvelope?.entries == [head])
    }

    @Test func definitiveRowCASClearsWorkerAndNeverFallsThrough()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let now = fixture.clock.now
        let first = try coordinatorOutboxEntry(
            index: 4,
            createdAt: now.addingTimeInterval(-20)
        )
        let second = try coordinatorOutboxEntry(
            index: 5,
            createdAt: now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [first, second]
            )
        )
        fixture.accepted.install(
            try IOSAcceptedHistoryEnvelope(revision: 1, entries: [])
        )
        fixture.accepted.failReplace(
            onCall: fixture.accepted.replaceCount + 1,
            with: .compareAndSwapFailed,
            commitBeforeThrowing: false
        )
        let coordinator = fixture.coordinator()

        #expect(
            try await coordinator.recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        #expect(await fixture.outboxWorkerState.current() == nil)
        #expect(fixture.outbox.currentEnvelope?.entries == [first, second])
        #expect(fixture.accepted.currentEnvelope?.entries.isEmpty == true)

        #expect(
            try await coordinator.recoverAcceptedHistoryOutbox() == .retired
        )
        #expect(fixture.outbox.currentEnvelope?.entries == [second])
    }

    @Test func definitiveMarkerCASClearsWorkerAndNeverFallsThrough()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let now = fixture.clock.now
        let first = try coordinatorOutboxEntry(
            index: 6,
            createdAt: now.addingTimeInterval(-20)
        )
        let second = try coordinatorOutboxEntry(
            index: 7,
            createdAt: now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [first, second]
            )
        )
        fixture.delivery.install(
            try coordinatorDeliveryRecord(
                matching: first,
                state: .pending
            )
        )
        fixture.delivery.failReplace(
            onCall: fixture.delivery.replaceCount + 3,
            with: .compareAndSwapFailed,
            commitBeforeThrowing: false
        )
        let coordinator = fixture.coordinator()

        #expect(
            try await coordinator.recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        #expect(await fixture.outboxWorkerState.current() == nil)
        #expect(fixture.outbox.currentEnvelope?.entries == [first, second])
        #expect(fixture.delivery.currentRecord?.historyWrite?.state == .pending)

        #expect(
            try await coordinator.recoverAcceptedHistoryOutbox() == .retired
        )
        #expect(fixture.outbox.currentEnvelope?.entries == [second])
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state == .committed
        )
    }

    @Test func missingAndEmptyOutboxDoNoDownstreamWork() async throws {
        for installsEmpty in [false, true] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            if installsEmpty {
                fixture.outbox.install(
                    try IOSAcceptedHistoryOutboxEnvelope(
                        revision: 1,
                        entries: []
                    )
                )
            }

            let result = try await fixture.coordinator()
                .recoverAcceptedHistoryOutbox()

            #expect(result == .noWork)
            #expect(fixture.policy.loadCount == 0)
            #expect(fixture.accepted.loadCount == 0)
            #expect(fixture.delivery.loadCount == 0)
            #expect(fixture.outbox.currentEnvelope?.entries.isEmpty != false)
        }
    }

    @Test func nonmatchingPolicyNeverMutatesOrSkipsTheHead() async throws {
        let scenarios: [(IOSHistoryPolicyState, Int64)] = [
            (
                try IOSHistoryPolicyState(
                    revision: 2,
                    historyEnabled: false,
                    policyGeneration: 2
                ),
                2
            ),
            (
                try IOSHistoryPolicyState(
                    revision: 1,
                    historyEnabled: true,
                    policyGeneration: 1
                ),
                2
            ),
            (
                try IOSHistoryPolicyState(
                    revision: 1,
                    historyEnabled: false,
                    policyGeneration: 1
                ),
                2
            ),
        ]

        for (policy, entryGeneration) in scenarios {
            let fixture = CoordinatorFixture()
            fixture.policy.install(policy)
            let now = fixture.clock.now
            let first = try coordinatorOutboxEntry(
                index: Int(policy.policyGeneration * 10),
                createdAt: now.addingTimeInterval(-20),
                generation: entryGeneration
            )
            let second = try coordinatorOutboxEntry(
                index: Int(policy.policyGeneration * 10 + 1),
                createdAt: now.addingTimeInterval(-10),
                generation: entryGeneration
            )
            fixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [first, second]
                )
            )

            #expect(
                try await fixture.coordinator()
                    .recoverAcceptedHistoryOutbox()
                    == .pendingLocalRecovery
            )
            #expect(fixture.outbox.currentEnvelope?.entries == [first, second])
            #expect(fixture.accepted.loadCount == 0)
            #expect(fixture.delivery.loadCount == 0)
            #expect(await fixture.outboxWorkerState.current() == nil)
        }
    }

    @Test func cancelledMarkerRequiresStrictlyNewerPolicy() async throws {
        let matching = CoordinatorFixture()
        matching.policy.install(.baseline)
        let matchingHead = try coordinatorOutboxEntry(
            index: 30,
            createdAt: matching.clock.now.addingTimeInterval(-10)
        )
        matching.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [matchingHead]
            )
        )
        matching.delivery.install(
            try coordinatorDeliveryRecord(
                matching: matchingHead,
                state: .cancelled
            )
        )

        #expect(
            try await matching.coordinator().recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        #expect(matching.outbox.currentEnvelope?.entries == [matchingHead])
        #expect(matching.accepted.loadCount == 0)

        let invalidated = CoordinatorFixture()
        invalidated.policy.install(
            try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: false,
                policyGeneration: 2
            )
        )
        let invalidatedHead = try coordinatorOutboxEntry(
            index: 31,
            createdAt: invalidated.clock.now.addingTimeInterval(-10)
        )
        invalidated.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [invalidatedHead]
            )
        )
        invalidated.delivery.install(
            try coordinatorDeliveryRecord(
                matching: invalidatedHead,
                state: .cancelled
            )
        )

        #expect(
            try await invalidated.coordinator()
                .recoverAcceptedHistoryOutbox() == .retired
        )
        #expect(invalidated.outbox.currentEnvelope?.entries.isEmpty == true)
        #expect(invalidated.accepted.loadCount == 0)
    }

    @Test func retainedCancellationCannotTargetUnrelatedDelivery()
        async throws {
        let fixture = CoordinatorFixture()
        let invalidatedPolicy = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: false,
            policyGeneration: 2
        )
        fixture.policy.install(invalidatedPolicy)
        let head = try coordinatorOutboxEntry(
            index: 32,
            createdAt: fixture.clock.now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [head]
            )
        )
        let observation = try #require(
            try await fixture.outboxStore.observeHead()
        )
        let membership = try await fixture.outboxStore.confirmMembership(
            observation: observation
        )
        let policy = try await fixture.policyStore.confirm(
            expected: IOSHistoryPolicyExpectation(state: invalidatedPolicy)
        )
        let unrelatedEntry = try coordinatorOutboxEntry(
            index: 33,
            createdAt: head.createdAt
        )
        let unrelatedRecord = try coordinatorDeliveryRecord(
            matching: unrelatedEntry,
            state: .pending
        )
        fixture.delivery.install(unrelatedRecord)
        let unrelatedAuthorization = try await fixture.deliveryStore
            .confirmActiveHistoryRecovery(
                expected: IOSAcceptedOutputDeliveryExpectation(
                    record: unrelatedRecord
                )
            )
        let deliveryReplaces = fixture.delivery.replaceCount
        await fixture.outboxWorkerState.store(
            IOSAcceptedHistoryOutboxWorkerWork(
                ownerIdentity: fixture.ownerIdentity,
                phase: .cancellationAuthorized(
                    membership,
                    policy,
                    unrelatedAuthorization
                )
            )
        )

        #expect(
            try await fixture.coordinator().recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        #expect(await fixture.outboxWorkerState.current() == nil)
        #expect(fixture.delivery.replaceCount == deliveryReplaces)
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state == .pending
        )
        #expect(fixture.outbox.currentEnvelope?.entries == [head])
    }

    @Test func eachInvocationRetiresOnlyTheCanonicalHead() async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let now = fixture.clock.now
        let first = try coordinatorOutboxEntry(
            index: 10,
            createdAt: now.addingTimeInterval(-20)
        )
        let second = try coordinatorOutboxEntry(
            index: 11,
            createdAt: now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [first, second]
            )
        )
        let coordinator = fixture.coordinator()

        #expect(
            try await coordinator.recoverAcceptedHistoryOutbox() == .retired
        )
        #expect(fixture.outbox.currentEnvelope?.entries == [second])
        #expect(
            fixture.accepted.currentEnvelope?.entries.map(\.deliveryID)
                == [first.deliveryID]
        )

        #expect(
            try await coordinator.recoverAcceptedHistoryOutbox() == .retired
        )
        #expect(fixture.outbox.currentEnvelope?.entries.isEmpty == true)
        #expect(
            Set(fixture.accepted.currentEnvelope?.entries.map(\.deliveryID) ?? [])
                == Set([first.deliveryID, second.deliveryID])
        )
    }

    @Test func capacityLossRetiresHeadWithoutChangingAcceptedEnvelope()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let now = fixture.clock.now
        let head = try coordinatorOutboxEntry(
            index: 20,
            createdAt: now.addingTimeInterval(-1_000)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [head]
            )
        )
        let rows = try (0..<20).map { offset in
            try coordinatorHistoryEntry(
                index: 100 + offset,
                createdAt: now.addingTimeInterval(Double(-offset))
            )
        }
        let accepted = try IOSAcceptedHistoryEnvelope(
            revision: 7,
            entries: IOSAcceptedHistoryValidation.sorted(rows)
        )
        fixture.accepted.install(accepted)

        #expect(
            try await fixture.coordinator().recoverAcceptedHistoryOutbox()
                == .retired
        )
        #expect(fixture.accepted.currentEnvelope == accepted)
        #expect(fixture.outbox.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func initialInvalidationCancelsExactMarkerWithoutRowWork()
        async throws {
        let fixture = CoordinatorFixture()
        let invalidated = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: false,
            policyGeneration: 2
        )
        fixture.policy.install(invalidated)
        let head = try coordinatorOutboxEntry(
            index: 30,
            createdAt: fixture.clock.now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [head]
            )
        )
        fixture.delivery.install(
            try coordinatorDeliveryRecord(
                matching: head,
                state: .pending
            )
        )

        #expect(
            try await fixture.coordinator().recoverAcceptedHistoryOutbox()
                == .retired
        )
        #expect(fixture.accepted.loadCount == 0)
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state == .cancelled
        )
        #expect(fixture.outbox.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func policyCutoverAfterRowDecisionCancelsAndRetires() async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let head = try coordinatorOutboxEntry(
            index: 40,
            createdAt: fixture.clock.now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [head]
            )
        )
        fixture.delivery.install(
            try coordinatorDeliveryRecord(
                matching: head,
                state: .pending
            )
        )
        fixture.policy.raceReplace(
            onCall: fixture.policy.replaceCount + 2,
            with: try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: false,
                policyGeneration: 2
            )
        )

        #expect(
            try await fixture.coordinator().recoverAcceptedHistoryOutbox()
                == .retired
        )
        #expect(
            fixture.accepted.currentEnvelope?.entries.map(\.deliveryID)
                == [head.deliveryID]
        )
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state == .cancelled
        )
        #expect(fixture.outbox.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func temporalExpiryRetiresAndRollbackNeverSkipsHead() async throws {
        let expiredFixture = CoordinatorFixture()
        expiredFixture.policy.install(.baseline)
        let expiredNow = expiredFixture.clock.now
        let expired = try coordinatorOutboxEntry(
            index: 50,
            createdAt: expiredNow.addingTimeInterval(-86_400)
        )
        expiredFixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [expired]
            )
        )
        #expect(
            try await expiredFixture.coordinator()
                .recoverAcceptedHistoryOutbox() == .retired
        )
        #expect(expiredFixture.policy.loadCount == 0)
        #expect(expiredFixture.accepted.loadCount == 0)
        #expect(expiredFixture.delivery.loadCount == 0)

        let rollbackFixture = CoordinatorFixture()
        rollbackFixture.policy.install(.baseline)
        let rollbackNow = rollbackFixture.clock.now
        let first = try coordinatorOutboxEntry(
            index: 51,
            createdAt: rollbackNow.addingTimeInterval(1)
        )
        let second = try coordinatorOutboxEntry(
            index: 52,
            createdAt: rollbackNow.addingTimeInterval(2)
        )
        rollbackFixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [first, second]
            )
        )
        #expect(
            try await rollbackFixture.coordinator()
                .recoverAcceptedHistoryOutbox() == .pendingLocalRecovery
        )
        #expect(rollbackFixture.outbox.currentEnvelope?.entries == [first, second])
        #expect(rollbackFixture.policy.loadCount == 0)
        #expect(rollbackFixture.accepted.loadCount == 0)
        #expect(rollbackFixture.delivery.loadCount == 0)
    }

    @Test func committedTerminalRetiresWithoutReevaluatingAbsentRow()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let head = try coordinatorOutboxEntry(
            index: 60,
            createdAt: fixture.clock.now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [head]
            )
        )
        fixture.accepted.install(
            try IOSAcceptedHistoryEnvelope(revision: 9, entries: [])
        )
        fixture.delivery.install(
            try coordinatorDeliveryRecord(
                matching: head,
                state: .committed
            )
        )

        #expect(
            try await fixture.relaunchedCoordinator()
                .recoverAcceptedHistoryOutbox() == .retired
        )
        #expect(fixture.accepted.currentEnvelope?.entries.isEmpty == true)
        #expect(fixture.accepted.loadCount == 0)
        #expect(fixture.outbox.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func identityCollisionBlocksHeadAndLaterEntry() async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let now = fixture.clock.now
        let first = try coordinatorOutboxEntry(
            index: 70,
            createdAt: now.addingTimeInterval(-20)
        )
        let second = try coordinatorOutboxEntry(
            index: 71,
            createdAt: now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [first, second]
            )
        )
        fixture.delivery.install(
            try coordinatorDeliveryRecord(
                matching: first,
                state: .pending,
                acceptedText: "different bytes"
            )
        )

        #expect(
            try await fixture.coordinator().recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        #expect(fixture.outbox.currentEnvelope?.entries == [first, second])
        #expect(fixture.accepted.loadCount == 0)
    }

    @Test func uncertaintyResumesExactPhaseAcrossSameRootCoordinator()
        async throws {
        for commitWasVisible in [false, true] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let now = fixture.clock.now
            let first = try coordinatorOutboxEntry(
                index: commitWasVisible ? 81 : 80,
                createdAt: now.addingTimeInterval(-20)
            )
            let second = try coordinatorOutboxEntry(
                index: commitWasVisible ? 83 : 82,
                createdAt: now.addingTimeInterval(-10)
            )
            fixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [first, second]
                )
            )
            fixture.outbox.failReplace(
                onCall: fixture.outbox.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            #expect(
                try await fixture.coordinator()
                    .recoverAcceptedHistoryOutbox() == .pendingLocalRecovery
            )
            #expect(
                try await fixture.coordinator()
                    .recoverAcceptedHistoryOutbox() == .retired
            )
            #expect(fixture.outbox.currentEnvelope?.entries == [second])
            #expect(
                fixture.accepted.currentEnvelope?.entries.filter {
                    $0.deliveryID == first.deliveryID
                }.count == 1
            )
        }
    }

    @Test func membershipAndPolicyUncertaintyResumeOnlyTheExactHead()
        async throws {
        for commitWasVisible in [false, true] {
            let membershipFixture = CoordinatorFixture()
            membershipFixture.policy.install(.baseline)
            let now = membershipFixture.clock.now
            let first = try coordinatorOutboxEntry(
                index: commitWasVisible ? 111 : 110,
                createdAt: now.addingTimeInterval(-20)
            )
            let second = try coordinatorOutboxEntry(
                index: commitWasVisible ? 113 : 112,
                createdAt: now.addingTimeInterval(-10)
            )
            membershipFixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [first, second]
                )
            )
            membershipFixture.outbox.failReplace(
                onCall: membershipFixture.outbox.replaceCount + 1,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )
            let membershipCoordinator = membershipFixture.coordinator()

            #expect(
                try await membershipCoordinator
                    .recoverAcceptedHistoryOutbox() == .pendingLocalRecovery
            )
            #expect(
                try await membershipCoordinator
                    .recoverAcceptedHistoryOutbox() == .retired
            )
            #expect(membershipFixture.outbox.currentEnvelope?.entries == [second])

            let policyFixture = CoordinatorFixture()
            policyFixture.policy.install(.baseline)
            let policyHead = try coordinatorOutboxEntry(
                index: commitWasVisible ? 121 : 120,
                createdAt: policyFixture.clock.now.addingTimeInterval(-10)
            )
            policyFixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [policyHead]
                )
            )
            policyFixture.policy.failReplace(
                onCall: policyFixture.policy.replaceCount + 1,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )
            let policyCoordinator = policyFixture.coordinator()

            #expect(
                try await policyCoordinator.recoverAcceptedHistoryOutbox()
                    == .pendingLocalRecovery
            )
            #expect(policyFixture.accepted.loadCount == 0)
            #expect(
                try await policyCoordinator.recoverAcceptedHistoryOutbox()
                    == .retired
            )
            #expect(policyFixture.outbox.currentEnvelope?.entries.isEmpty == true)
        }
    }

    @Test func rowAndPolicyRevalidationUncertaintyDoNotRepeatDecisions()
        async throws {
        for commitWasVisible in [false, true] {
            let rowFixture = CoordinatorFixture()
            rowFixture.policy.install(.baseline)
            let rowHead = try coordinatorOutboxEntry(
                index: commitWasVisible ? 131 : 130,
                createdAt: rowFixture.clock.now.addingTimeInterval(-10)
            )
            rowFixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [rowHead]
                )
            )
            rowFixture.accepted.failNextCreate(
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )
            let rowCoordinator = rowFixture.coordinator()

            #expect(
                try await rowCoordinator.recoverAcceptedHistoryOutbox()
                    == .pendingLocalRecovery
            )
            #expect(
                try await rowCoordinator.recoverAcceptedHistoryOutbox()
                    == .retired
            )
            #expect(
                rowFixture.accepted.currentEnvelope?.entries.map(\.deliveryID)
                    == [rowHead.deliveryID]
            )

            let policyFixture = CoordinatorFixture()
            policyFixture.policy.install(.baseline)
            let policyHead = try coordinatorOutboxEntry(
                index: commitWasVisible ? 141 : 140,
                createdAt: policyFixture.clock.now.addingTimeInterval(-10)
            )
            policyFixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [policyHead]
                )
            )
            policyFixture.policy.failReplace(
                onCall: policyFixture.policy.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )
            let policyCoordinator = policyFixture.coordinator()

            #expect(
                try await policyCoordinator.recoverAcceptedHistoryOutbox()
                    == .pendingLocalRecovery
            )
            let acceptedCreates = policyFixture.accepted.createCount
            #expect(
                try await policyCoordinator.recoverAcceptedHistoryOutbox()
                    == .retired
            )
            #expect(policyFixture.accepted.createCount == acceptedCreates)
        }
    }

    @Test func deliveryAndMarkerUncertaintyResumeWithoutRepeatingTheRow()
        async throws {
        for commitWasVisible in [false, true] {
            let confirmationFixture = CoordinatorFixture()
            confirmationFixture.policy.install(.baseline)
            let confirmationHead = try coordinatorOutboxEntry(
                index: commitWasVisible ? 151 : 150,
                createdAt: confirmationFixture.clock.now
                    .addingTimeInterval(-10)
            )
            confirmationFixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [confirmationHead]
                )
            )
            confirmationFixture.delivery.install(
                try coordinatorDeliveryRecord(
                    matching: confirmationHead,
                    state: .pending
                )
            )
            confirmationFixture.delivery.failReplace(
                onCall: confirmationFixture.delivery.replaceCount + 1,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )
            let confirmationCoordinator = confirmationFixture.coordinator()

            #expect(
                try await confirmationCoordinator
                    .recoverAcceptedHistoryOutbox() == .pendingLocalRecovery
            )
            #expect(confirmationFixture.accepted.loadCount == 0)
            #expect(
                try await confirmationCoordinator
                    .recoverAcceptedHistoryOutbox() == .retired
            )

            let markerFixture = CoordinatorFixture()
            markerFixture.policy.install(.baseline)
            let markerHead = try coordinatorOutboxEntry(
                index: commitWasVisible ? 161 : 160,
                createdAt: markerFixture.clock.now.addingTimeInterval(-10)
            )
            markerFixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [markerHead]
                )
            )
            markerFixture.delivery.install(
                try coordinatorDeliveryRecord(
                    matching: markerHead,
                    state: .pending
                )
            )
            markerFixture.delivery.failReplace(
                onCall: markerFixture.delivery.replaceCount + 3,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )
            let markerCoordinator = markerFixture.coordinator()

            #expect(
                try await markerCoordinator.recoverAcceptedHistoryOutbox()
                    == .pendingLocalRecovery
            )
            let acceptedCreates = markerFixture.accepted.createCount
            #expect(
                try await markerCoordinator.recoverAcceptedHistoryOutbox()
                    == .retired
            )
            #expect(markerFixture.accepted.createCount == acceptedCreates)
            #expect(
                markerFixture.delivery.currentRecord?.historyWrite?.state
                    == .committed
            )
        }
    }

    @Test func laterDeliveryConfirmationsResumeExactWorkerPhase()
        async throws {
        for commitWasVisible in [false, true] {
            let postRow = CoordinatorFixture()
            postRow.policy.install(.baseline)
            let postRowNow = postRow.clock.now
            let postRowHead = try coordinatorOutboxEntry(
                index: commitWasVisible ? 165 : 164,
                createdAt: postRowNow.addingTimeInterval(-20)
            )
            let postRowNext = try coordinatorOutboxEntry(
                index: commitWasVisible ? 167 : 166,
                createdAt: postRowNow.addingTimeInterval(-10)
            )
            postRow.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [postRowHead, postRowNext]
                )
            )
            postRow.delivery.install(
                try coordinatorDeliveryRecord(
                    matching: postRowHead,
                    state: .pending
                )
            )
            postRow.delivery.failReplace(
                onCall: postRow.delivery.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )
            let postRowCoordinator = postRow.coordinator()

            #expect(
                try await postRowCoordinator.recoverAcceptedHistoryOutbox()
                    == .pendingLocalRecovery
            )
            #expect(
                postRow.accepted.currentEnvelope?.entries.map(\.deliveryID)
                    == [postRowHead.deliveryID]
            )
            #expect(postRow.outbox.currentEnvelope?.entries == [
                postRowHead,
                postRowNext,
            ])
            let postRowCounts = (
                postRow.policy.loadCount,
                postRow.policy.replaceCount,
                postRow.accepted.loadCount,
                postRow.accepted.createCount,
                postRow.accepted.replaceCount
            )

            #expect(
                try await postRowCoordinator.recoverAcceptedHistoryOutbox()
                    == .retired
            )
            #expect(postRow.policy.loadCount == postRowCounts.0)
            #expect(postRow.policy.replaceCount == postRowCounts.1)
            #expect(postRow.accepted.loadCount == postRowCounts.2)
            #expect(postRow.accepted.createCount == postRowCounts.3)
            #expect(postRow.accepted.replaceCount == postRowCounts.4)
            #expect(postRow.outbox.currentEnvelope?.entries == [postRowNext])
            #expect(
                postRow.delivery.currentRecord?.historyWrite?.state
                    == .committed
            )

            let invalidation = CoordinatorFixture()
            invalidation.policy.install(
                try IOSHistoryPolicyState(
                    revision: 2,
                    historyEnabled: true,
                    policyGeneration: 2
                )
            )
            let invalidationNow = invalidation.clock.now
            let invalidationHead = try coordinatorOutboxEntry(
                index: commitWasVisible ? 175 : 174,
                createdAt: invalidationNow.addingTimeInterval(-20)
            )
            let invalidationNext = try coordinatorOutboxEntry(
                index: commitWasVisible ? 177 : 176,
                createdAt: invalidationNow.addingTimeInterval(-10)
            )
            invalidation.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [invalidationHead, invalidationNext]
                )
            )
            invalidation.delivery.install(
                try coordinatorDeliveryRecord(
                    matching: invalidationHead,
                    state: .pending
                )
            )
            invalidation.delivery.failReplace(
                onCall: invalidation.delivery.replaceCount + 1,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )
            let invalidationCoordinator = invalidation.coordinator()

            #expect(
                try await invalidationCoordinator.recoverAcceptedHistoryOutbox()
                    == .pendingLocalRecovery
            )
            #expect(invalidation.accepted.loadCount == 0)
            #expect(invalidation.outbox.currentEnvelope?.entries == [
                invalidationHead,
                invalidationNext,
            ])
            let invalidationCounts = (
                invalidation.policy.loadCount,
                invalidation.policy.replaceCount,
                invalidation.accepted.loadCount
            )

            #expect(
                try await invalidationCoordinator.recoverAcceptedHistoryOutbox()
                    == .retired
            )
            #expect(invalidation.policy.loadCount == invalidationCounts.0)
            #expect(invalidation.policy.replaceCount == invalidationCounts.1)
            #expect(invalidation.accepted.loadCount == invalidationCounts.2)
            #expect(
                invalidation.outbox.currentEnvelope?.entries
                    == [invalidationNext]
            )
            #expect(
                invalidation.delivery.currentRecord?.historyWrite?.state
                    == .cancelled
            )
        }
    }

    @Test func cancellationUncertaintyResumesWithoutAnyRowDecision()
        async throws {
        for commitWasVisible in [false, true] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(
                try IOSHistoryPolicyState(
                    revision: 2,
                    historyEnabled: false,
                    policyGeneration: 2
                )
            )
            let head = try coordinatorOutboxEntry(
                index: commitWasVisible ? 171 : 170,
                createdAt: fixture.clock.now.addingTimeInterval(-10)
            )
            fixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [head]
                )
            )
            fixture.delivery.install(
                try coordinatorDeliveryRecord(
                    matching: head,
                    state: .pending
                )
            )
            fixture.delivery.failReplace(
                onCall: fixture.delivery.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )
            let coordinator = fixture.coordinator()

            #expect(
                try await coordinator.recoverAcceptedHistoryOutbox()
                    == .pendingLocalRecovery
            )
            #expect(fixture.accepted.loadCount == 0)
            #expect(
                try await coordinator.recoverAcceptedHistoryOutbox()
                    == .retired
            )
            #expect(fixture.accepted.loadCount == 0)
            #expect(
                fixture.delivery.currentRecord?.historyWrite?.state
                    == .cancelled
            )
        }
    }

    @Test func processLossReconstructsMembershipAndRetirementUncertainty()
        async throws {
        for commitWasVisible in [false, true] {
            let membershipFixture = CoordinatorFixture()
            membershipFixture.policy.install(.baseline)
            let membershipHead = try coordinatorOutboxEntry(
                index: commitWasVisible ? 181 : 180,
                createdAt: membershipFixture.clock.now.addingTimeInterval(-10)
            )
            membershipFixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [membershipHead]
                )
            )
            membershipFixture.outbox.failReplace(
                onCall: membershipFixture.outbox.replaceCount + 1,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            #expect(
                try await membershipFixture.coordinator()
                    .recoverAcceptedHistoryOutbox() == .pendingLocalRecovery
            )
            #expect(
                try await membershipFixture.relaunchedCoordinator()
                    .recoverAcceptedHistoryOutbox() == .retired
            )
            #expect(
                membershipFixture.accepted.currentEnvelope?.entries
                    .map(\.deliveryID) == [membershipHead.deliveryID]
            )
            #expect(
                membershipFixture.outbox.currentEnvelope?.entries.isEmpty
                    == true
            )

            let retirementFixture = CoordinatorFixture()
            retirementFixture.policy.install(.baseline)
            let retirementHead = try coordinatorOutboxEntry(
                index: commitWasVisible ? 183 : 182,
                createdAt: retirementFixture.clock.now.addingTimeInterval(-10)
            )
            retirementFixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [retirementHead]
                )
            )
            retirementFixture.outbox.failReplace(
                onCall: retirementFixture.outbox.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            #expect(
                try await retirementFixture.coordinator()
                    .recoverAcceptedHistoryOutbox() == .pendingLocalRecovery
            )
            let relaunchedResolution = try await retirementFixture
                .relaunchedCoordinator().recoverAcceptedHistoryOutbox()
            #expect(
                relaunchedResolution == (commitWasVisible ? .noWork : .retired)
            )
            #expect(
                retirementFixture.accepted.currentEnvelope?.entries
                    .map(\.deliveryID) == [retirementHead.deliveryID]
            )
            #expect(
                retirementFixture.outbox.currentEnvelope?.entries.isEmpty
                    == true
            )
        }
    }

    @Test func processLossReplaysNotRetainedAndNewerPolicyTerminalBoundaries()
        async throws {
        let capacityFixture = CoordinatorFixture()
        capacityFixture.policy.install(.baseline)
        let capacityNow = capacityFixture.clock.now
        let capacityHead = try coordinatorOutboxEntry(
            index: 190,
            createdAt: capacityNow.addingTimeInterval(-1_000)
        )
        capacityFixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [capacityHead]
            )
        )
        let retainedRows = try (0..<20).map { offset in
            try coordinatorHistoryEntry(
                index: 1_000 + offset,
                createdAt: capacityNow.addingTimeInterval(Double(-offset))
            )
        }
        let retainedEnvelope = try IOSAcceptedHistoryEnvelope(
            revision: 7,
            entries: IOSAcceptedHistoryValidation.sorted(retainedRows)
        )
        capacityFixture.accepted.install(retainedEnvelope)
        capacityFixture.outbox.failReplace(
            onCall: capacityFixture.outbox.replaceCount + 2,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )

        #expect(
            try await capacityFixture.coordinator()
                .recoverAcceptedHistoryOutbox() == .pendingLocalRecovery
        )
        #expect(capacityFixture.accepted.currentEnvelope == retainedEnvelope)
        #expect(
            try await capacityFixture.relaunchedCoordinator()
                .recoverAcceptedHistoryOutbox() == .retired
        )
        #expect(capacityFixture.accepted.currentEnvelope == retainedEnvelope)
        #expect(capacityFixture.outbox.currentEnvelope?.entries.isEmpty == true)

        for (offset, state) in [
            IOSAcceptedOutputHistoryWriteState.cancelled,
            .committed,
        ].enumerated() {
            let fixture = CoordinatorFixture()
            fixture.policy.install(
                try IOSHistoryPolicyState(
                    revision: 2,
                    historyEnabled: true,
                    policyGeneration: 2
                )
            )
            let head = try coordinatorOutboxEntry(
                index: 191 + offset,
                createdAt: fixture.clock.now.addingTimeInterval(-10)
            )
            fixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [head]
                )
            )
            fixture.delivery.install(
                try coordinatorDeliveryRecord(matching: head, state: state)
            )

            #expect(
                try await fixture.relaunchedCoordinator()
                    .recoverAcceptedHistoryOutbox() == .retired
            )
            #expect(fixture.accepted.loadCount == 0)
            #expect(fixture.delivery.currentRecord?.historyWrite?.state == state)
            #expect(fixture.outbox.currentEnvelope?.entries.isEmpty == true)
        }
    }

    @Test func terminalRetirementUncertaintyAndCASNeverSkipTheNextHead()
        async throws {
        let cases: [(IOSAcceptedHistoryOutboxError, Bool)] = [
            (.commitUncertain, false),
            (.commitUncertain, true),
            (.compareAndSwapFailed, false),
        ]
        for (offset, scenario) in cases.enumerated() {
            let (error, commitWasVisible) = scenario
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let now = fixture.clock.now
            let first = try coordinatorOutboxEntry(
                index: 200 + offset * 2,
                createdAt: now.addingTimeInterval(-20)
            )
            let second = try coordinatorOutboxEntry(
                index: 201 + offset * 2,
                createdAt: now.addingTimeInterval(-10)
            )
            fixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [first, second]
                )
            )
            fixture.delivery.install(
                try coordinatorDeliveryRecord(
                    matching: first,
                    state: .committed
                )
            )
            fixture.outbox.failReplace(
                onCall: fixture.outbox.replaceCount + 2,
                with: error,
                commitBeforeThrowing: commitWasVisible
            )
            let coordinator = fixture.coordinator()

            #expect(
                try await coordinator.recoverAcceptedHistoryOutbox()
                    == .pendingLocalRecovery
            )
            #expect(fixture.accepted.loadCount == 0)
            #expect(
                fixture.outbox.currentEnvelope?.entries
                    == (commitWasVisible ? [second] : [first, second])
            )
            if error == .compareAndSwapFailed {
                #expect(await fixture.outboxWorkerState.current() == nil)
            } else {
                #expect(await fixture.outboxWorkerState.current() != nil)
            }

            #expect(
                try await coordinator.recoverAcceptedHistoryOutbox() == .retired
            )
            #expect(fixture.outbox.currentEnvelope?.entries == [second])
            #expect(fixture.accepted.loadCount == 0)
        }
    }

    @Test func newerEnabledPolicyInvalidatesBeforeAndAfterRowDecision()
        async throws {
        let before = CoordinatorFixture()
        before.policy.install(
            try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: true,
                policyGeneration: 2
            )
        )
        let beforeHead = try coordinatorOutboxEntry(
            index: 210,
            createdAt: before.clock.now.addingTimeInterval(-10)
        )
        before.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [beforeHead]
            )
        )
        before.delivery.install(
            try coordinatorDeliveryRecord(matching: beforeHead, state: .pending)
        )

        #expect(
            try await before.coordinator().recoverAcceptedHistoryOutbox()
                == .retired
        )
        #expect(before.accepted.loadCount == 0)
        #expect(before.delivery.currentRecord?.historyWrite?.state == .cancelled)
        #expect(before.outbox.currentEnvelope?.entries.isEmpty == true)

        let after = CoordinatorFixture()
        after.policy.install(.baseline)
        let afterHead = try coordinatorOutboxEntry(
            index: 211,
            createdAt: after.clock.now.addingTimeInterval(-10)
        )
        after.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [afterHead]
            )
        )
        after.delivery.install(
            try coordinatorDeliveryRecord(matching: afterHead, state: .pending)
        )
        after.policy.raceReplace(
            onCall: after.policy.replaceCount + 2,
            with: try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: true,
                policyGeneration: 2
            )
        )

        #expect(
            try await after.coordinator().recoverAcceptedHistoryOutbox()
                == .retired
        )
        #expect(
            after.accepted.currentEnvelope?.entries.map(\.deliveryID)
                == [afterHead.deliveryID]
        )
        #expect(after.delivery.currentRecord?.historyWrite?.state == .cancelled)
        #expect(after.outbox.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func discardedAndMatchingTemporalDeliveryBranchesAreExact()
        async throws {
        let discarded = CoordinatorFixture()
        discarded.policy.install(.baseline)
        let discardedHead = try coordinatorOutboxEntry(
            index: 220,
            createdAt: discarded.clock.now.addingTimeInterval(-10)
        )
        discarded.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [discardedHead]
            )
        )
        discarded.delivery.install(
            try coordinatorDiscardedDeliveryRecord(matching: discardedHead)
        )

        #expect(
            try await discarded.coordinator().recoverAcceptedHistoryOutbox()
                == .retired
        )
        #expect(
            discarded.accepted.currentEnvelope?.entries.map(\.deliveryID)
                == [discardedHead.deliveryID]
        )
        #expect(discarded.delivery.currentRecord?.deliveryState == .discarded)
        #expect(discarded.outbox.currentEnvelope?.entries.isEmpty == true)

        let expired = CoordinatorFixture()
        expired.policy.install(.baseline)
        let expiredHead = try coordinatorOutboxEntry(
            index: 221,
            createdAt: expired.clock.now.addingTimeInterval(-10)
        )
        expired.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [expiredHead]
            )
        )
        expired.delivery.install(
            try coordinatorDeliveryRecord(matching: expiredHead, state: .pending)
        )
        let expiryBlocker = CoordinatorBoundaryBlocker()
        expired.delivery.blockLoad(
            onCall: expired.delivery.loadCount + 1,
            with: expiryBlocker
        )
        let expiryRecovery = Task {
            try await expired.coordinator().recoverAcceptedHistoryOutbox()
        }
        #expect(expiryBlocker.waitUntilBlocked())
        expired.clock.advance(seconds: 86_400)
        expiryBlocker.open()

        #expect(try await expiryRecovery.value == .pendingLocalRecovery)
        #expect(expired.accepted.loadCount == 0)
        #expect(expired.outbox.currentEnvelope?.entries == [expiredHead])
        #expect(
            try await expired.coordinator().recoverAcceptedHistoryOutbox()
                == .retired
        )
        #expect(expired.accepted.loadCount == 0)

        let expiredAfterRow = CoordinatorFixture()
        expiredAfterRow.policy.install(.baseline)
        let expiredAfterRowHead = try coordinatorOutboxEntry(
            index: 223,
            createdAt: expiredAfterRow.clock.now.addingTimeInterval(-10)
        )
        expiredAfterRow.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [expiredAfterRowHead]
            )
        )
        expiredAfterRow.delivery.install(
            try coordinatorDeliveryRecord(
                matching: expiredAfterRowHead,
                state: .pending
            )
        )
        let postRowExpiryBlocker = CoordinatorBoundaryBlocker()
        expiredAfterRow.delivery.blockLoad(
            onCall: expiredAfterRow.delivery.loadCount + 2,
            with: postRowExpiryBlocker
        )
        let postRowExpiryRecovery = Task {
            try await expiredAfterRow.coordinator()
                .recoverAcceptedHistoryOutbox()
        }
        #expect(postRowExpiryBlocker.waitUntilBlocked())
        expiredAfterRow.clock.advance(seconds: 86_400)
        postRowExpiryBlocker.open()

        #expect(try await postRowExpiryRecovery.value == .retired)
        #expect(
            expiredAfterRow.accepted.currentEnvelope?.entries.map(\.deliveryID)
                == [expiredAfterRowHead.deliveryID]
        )
        #expect(
            expiredAfterRow.outbox.currentEnvelope?.entries.isEmpty == true
        )

        let rollback = CoordinatorFixture()
        rollback.policy.install(.baseline)
        let rollbackHead = try coordinatorOutboxEntry(
            index: 222,
            createdAt: rollback.clock.now.addingTimeInterval(-10)
        )
        rollback.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [rollbackHead]
            )
        )
        rollback.delivery.install(
            try coordinatorDeliveryRecord(matching: rollbackHead, state: .pending)
        )
        let rollbackBlocker = CoordinatorBoundaryBlocker()
        rollback.delivery.blockLoad(
            onCall: rollback.delivery.loadCount + 1,
            with: rollbackBlocker
        )
        let rollbackRecovery = Task {
            try await rollback.coordinator().recoverAcceptedHistoryOutbox()
        }
        #expect(rollbackBlocker.waitUntilBlocked())
        rollback.clock.rollBack(seconds: 20)
        rollbackBlocker.open()

        #expect(try await rollbackRecovery.value == .pendingLocalRecovery)
        #expect(rollback.accepted.loadCount == 0)
        #expect(rollback.outbox.currentEnvelope?.entries == [rollbackHead])
        #expect(
            try await rollback.coordinator().recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        #expect(rollback.accepted.loadCount == 0)
        #expect(rollback.outbox.currentEnvelope?.entries == [rollbackHead])
    }

    @Test func equalTimeUUIDHeadAndReadFailuresNeverSkip() async throws {
        let tied = CoordinatorFixture()
        tied.policy.install(.baseline)
        let tiedDate = tied.clock.now.addingTimeInterval(-10)
        let lowerUUID = try coordinatorOutboxEntry(
            index: 230,
            createdAt: tiedDate
        )
        let higherUUID = try coordinatorOutboxEntry(
            index: 231,
            createdAt: tiedDate
        )
        tied.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: IOSAcceptedHistoryOutboxValidation.sorted([
                    higherUUID,
                    lowerUUID,
                ])
            )
        )

        #expect(
            try await tied.coordinator().recoverAcceptedHistoryOutbox()
                == .retired
        )
        #expect(tied.outbox.currentEnvelope?.entries == [higherUUID])
        #expect(
            tied.accepted.currentEnvelope?.entries.map(\.deliveryID)
                == [lowerUUID.deliveryID]
        )

        for (offset, error) in [
            IOSAcceptedHistoryOutboxError.malformedData,
            .dataProtectionUnavailable,
            .sourceTooLarge,
        ].enumerated() {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let now = fixture.clock.now
            let first = try coordinatorOutboxEntry(
                index: 240 + offset * 2,
                createdAt: now.addingTimeInterval(-20)
            )
            let second = try coordinatorOutboxEntry(
                index: 241 + offset * 2,
                createdAt: now.addingTimeInterval(-10)
            )
            fixture.outbox.install(
                try IOSAcceptedHistoryOutboxEnvelope(
                    revision: 1,
                    entries: [first, second]
                )
            )
            fixture.outbox.failNextLoad(with: error)
            let coordinator = fixture.coordinator()

            #expect(
                try await coordinator.recoverAcceptedHistoryOutbox()
                    == .pendingLocalRecovery
            )
            #expect(fixture.outbox.currentEnvelope?.entries == [first, second])
            #expect(fixture.policy.loadCount == 0)
            #expect(fixture.accepted.loadCount == 0)
            #expect(fixture.delivery.loadCount == 0)
            #expect(await fixture.outboxWorkerState.current() == nil)

            #expect(
                try await coordinator.recoverAcceptedHistoryOutbox() == .retired
            )
            #expect(fixture.outbox.currentEnvelope?.entries == [second])
            #expect(
                fixture.accepted.currentEnvelope?.entries.map(\.deliveryID)
                    == [first.deliveryID]
            )
        }
    }

    @Test func retainedWorkerPhaseBlocksCaptureAcceptAndDeliveryRecovery()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let preparation = try await coordinatorPreparation(using: coordinator)
        let head = try coordinatorOutboxEntry(
            index: 90,
            createdAt: fixture.clock.now.addingTimeInterval(-10)
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [head]
            )
        )
        fixture.outbox.failReplace(
            onCall: fixture.outbox.replaceCount + 1,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        #expect(
            try await coordinator.recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        let policyLoads = fixture.policy.loadCount
        let deliveryLoads = fixture.delivery.loadCount

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await coordinator.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await coordinator.accept(preparation)
        }
        #expect(
            try await coordinator.recoverAcceptedHistory()
                == .pendingLocalRecovery
        )
        #expect(fixture.policy.loadCount == policyLoads)
        #expect(fixture.delivery.loadCount == deliveryLoads)
    }

    @Test func retainedAcceptanceAndReplacementPreventWorkerObservation()
        async throws {
        let acceptanceFixture = CoordinatorFixture()
        acceptanceFixture.policy.install(.baseline)
        let acceptanceCoordinator = acceptanceFixture.coordinator()
        let preparation = try await coordinatorPreparation(
            using: acceptanceCoordinator
        )
        let accepted = try await acceptanceFixture.deliveryStore.accept(
            preparation
        )
        await acceptanceFixture.acceptanceState.store(
            .fresh(preparation, .deliveryAccepted(accepted))
        )
        let acceptanceHead = try coordinatorOutboxEntry(
            index: 91,
            createdAt: acceptanceFixture.clock.now.addingTimeInterval(-10)
        )
        acceptanceFixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [acceptanceHead]
            )
        )
        let acceptanceOutboxLoads = acceptanceFixture.outbox.loadCount

        #expect(
            try await acceptanceCoordinator.recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        #expect(acceptanceFixture.outbox.loadCount == acceptanceOutboxLoads)
        #expect(await acceptanceFixture.outboxWorkerState.current() == nil)

        let replacementFixture = CoordinatorFixture()
        replacementFixture.policy.install(.baseline)
        let replacementCoordinator = replacementFixture.coordinator()
        let replacementPreparation = try await coordinatorPreparation(
            using: replacementCoordinator
        )
        await replacementFixture.pendingReplacementState.store(
            IOSAcceptedHistoryPendingReplacementWork(
                ownerIdentity: replacementFixture.ownerIdentity,
                preparation: replacementPreparation,
                phase: .observingCurrentDelivery
            )
        )
        let replacementHead = try coordinatorOutboxEntry(
            index: 92,
            createdAt: replacementFixture.clock.now.addingTimeInterval(-10)
        )
        replacementFixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [replacementHead]
            )
        )
        let replacementOutboxLoads = replacementFixture.outbox.loadCount

        #expect(
            try await replacementCoordinator.recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        #expect(replacementFixture.outbox.loadCount == replacementOutboxLoads)
        #expect(await replacementFixture.outboxWorkerState.current() == nil)
    }

    @Test func workerValuesAndResultAreRedacted() async throws {
        let fixture = CoordinatorFixture()
        let entry = try coordinatorOutboxEntry(
            index: 100,
            createdAt: fixture.clock.now
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [entry]
            )
        )
        let observation = try #require(
            try await fixture.outboxStore.observeHead()
        )
        let work = IOSAcceptedHistoryOutboxWorkerWork(
            ownerIdentity: fixture.ownerIdentity,
            phase: .headObserved(observation)
        )

        #expect(
            String(describing: work)
                == "IOSAcceptedHistoryOutboxWorkerWork(redacted)"
        )
        #expect(work.customMirror.children.isEmpty)
        #expect(!String(reflecting: work).contains(entry.acceptedText))
        #expect(
            String(describing:
                IOSAcceptedHistoryOutboxRecoveryResolution.retired)
                == "IOSAcceptedHistoryOutboxRecoveryResolution(redacted)"
        )
    }
}

struct IOSHistoryPolicyCutoverCoordinatorTests {
    @Test func clearAndTogglesAdvancePolicyExactlyOnce() async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let coordinator = fixture.coordinator()
        let cleared = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: true,
            policyGeneration: 2
        )
        let disabled = try IOSHistoryPolicyState(
            revision: 3,
            historyEnabled: false,
            policyGeneration: 3
        )
        let reenabled = try IOSHistoryPolicyState(
            revision: 4,
            historyEnabled: true,
            policyGeneration: 4
        )

        #expect(try await coordinator.clearHistoryPolicy() == .complete)
        #expect(fixture.policy.currentState == cleared)

        #expect(
            try await coordinator.setHistoryEnabled(true) == .complete
        )
        #expect(fixture.policy.currentState?.revision == 2)

        #expect(
            try await coordinator.setHistoryEnabled(false) == .complete
        )
        #expect(fixture.policy.currentState == disabled)

        #expect(
            try await coordinator.setHistoryEnabled(false) == .complete
        )
        #expect(fixture.policy.currentState?.revision == 3)

        #expect(
            try await coordinator.setHistoryEnabled(true) == .complete
        )
        #expect(fixture.policy.currentState == reenabled)
    }

    @Test func uncertainPolicyCutoverRequiresTheExactSameCommand()
        async throws {
        for commitWasVisible in [true, false] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let coordinator = fixture.coordinator()
            let expected = try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: true,
                policyGeneration: 2
            )
            fixture.policy.failReplace(
                onCall: fixture.policy.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
                _ = try await coordinator.clearHistoryPolicy()
            }
            #expect(fixture.accepted.loadCount == 0)
            #expect(fixture.outbox.loadCount == 0)
            #expect(fixture.delivery.loadCount == 0)
            let policyReplaceCount = fixture.policy.replaceCount

            await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
                _ = try await coordinator.setHistoryEnabled(false)
            }
            #expect(fixture.policy.replaceCount == policyReplaceCount)
            #expect(fixture.accepted.loadCount == 0)
            #expect(fixture.outbox.loadCount == 0)
            #expect(fixture.delivery.loadCount == 0)

            #expect(try await coordinator.clearHistoryPolicy() == .complete)
            #expect(fixture.policy.currentState == expected)
        }
    }

    @Test func committedCutoverReturnsPendingUntilExactCleanupRecovers()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let stale = try coordinatorHistoryEntry(
            index: 300,
            createdAt: fixture.clock.now,
            generation: 1
        )
        fixture.accepted.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 1,
                entries: [stale]
            )
        )
        fixture.accepted.failReplace(
            onCall: fixture.accepted.replaceCount + 1,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        let coordinator = fixture.coordinator()

        #expect(
            try await coordinator.clearHistoryPolicy()
                == .pendingLocalRecovery
        )
        #expect(fixture.policy.currentState?.revision == 2)
        #expect(fixture.accepted.currentEnvelope?.entries == [stale])
        #expect(fixture.outbox.loadCount == 0)
        #expect(fixture.delivery.loadCount == 0)
        #expect(await fixture.policyCutoverState.current() != nil)

        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            _ = try await coordinator.setHistoryEnabled(false)
        }
        #expect(fixture.policy.currentState?.revision == 2)

        #expect(
            try await coordinator.clearHistoryPolicy() == .complete
        )
        #expect(fixture.policy.currentState?.revision == 2)
        #expect(fixture.accepted.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func relaunchedCleanupKeepsCurrentRowsAndCancelsOnlyStalePending()
        async throws {
        let fixture = CoordinatorFixture()
        let policy = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: false,
            policyGeneration: 2
        )
        fixture.policy.install(policy)
        let stale = try coordinatorHistoryEntry(
            index: 301,
            createdAt: fixture.clock.now.addingTimeInterval(-1),
            generation: 1
        )
        let current = try coordinatorHistoryEntry(
            index: 302,
            createdAt: fixture.clock.now,
            generation: 2
        )
        fixture.accepted.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 4,
                entries: [current, stale]
            )
        )
        let staleDelivery = try coordinatorOutboxEntry(
            index: 303,
            createdAt: fixture.clock.now,
            generation: 1
        )
        fixture.delivery.install(
            try coordinatorDeliveryRecord(
                matching: staleDelivery,
                state: .pending
            )
        )

        #expect(
            try await fixture.relaunchedCoordinator()
                .recoverHistoryPolicyCleanup() == .complete
        )
        #expect(fixture.policy.currentState == policy)
        #expect(fixture.accepted.currentEnvelope?.entries == [current])
        #expect(
            fixture.delivery.currentRecord?.historyWrite?.state == .cancelled
        )
    }

    @Test func cutoverProcessesAtMostOneOutboxHeadPerCall() async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let now = fixture.clock.now
        let first = try coordinatorOutboxEntry(
            index: 304,
            createdAt: now.addingTimeInterval(-2),
            generation: 1
        )
        let second = try coordinatorOutboxEntry(
            index: 305,
            createdAt: now.addingTimeInterval(-1),
            generation: 1
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [first, second]
            )
        )
        let coordinator = fixture.coordinator()

        #expect(
            try await coordinator.clearHistoryPolicy()
                == .pendingLocalRecovery
        )
        #expect(fixture.outbox.currentEnvelope?.entries == [second])
        #expect(fixture.policy.currentState?.revision == 2)
        #expect(await fixture.policyCutoverState.current() != nil)

        #expect(
            try await coordinator.clearHistoryPolicy()
                == .pendingLocalRecovery
        )
        #expect(fixture.outbox.currentEnvelope?.entries.isEmpty == true)
        #expect(fixture.policy.currentState?.revision == 2)
        #expect(await fixture.policyCutoverState.current() != nil)

        #expect(
            try await coordinator.clearHistoryPolicy() == .complete
        )
        #expect(fixture.policy.currentState?.revision == 2)
    }

    @Test func postBoundaryCASAndExpiryRetainCutoverRecoveryState()
        async throws {
        let casFixture = CoordinatorFixture()
        casFixture.policy.install(.baseline)
        let stale = try coordinatorHistoryEntry(
            index: 313,
            createdAt: casFixture.clock.now,
            generation: 1
        )
        casFixture.accepted.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 1,
                entries: [stale]
            )
        )
        casFixture.accepted.failReplace(
            onCall: casFixture.accepted.replaceCount + 1,
            with: .compareAndSwapFailed,
            commitBeforeThrowing: false
        )

        #expect(
            try await casFixture.coordinator().clearHistoryPolicy()
                == .pendingLocalRecovery
        )
        #expect(casFixture.policy.currentState?.revision == 2)
        #expect(await casFixture.policyCutoverState.current() != nil)

        let expiryFixture = CoordinatorFixture()
        expiryFixture.policy.install(.baseline)
        let expiredEntry = try coordinatorOutboxEntry(
            index: 314,
            createdAt: expiryFixture.clock.now.addingTimeInterval(-86_400),
            generation: 1
        )
        expiryFixture.delivery.install(
            try coordinatorDeliveryRecord(
                matching: expiredEntry,
                state: .pending
            )
        )

        #expect(
            try await expiryFixture.coordinator().clearHistoryPolicy()
                == .pendingLocalRecovery
        )
        #expect(expiryFixture.policy.currentState?.revision == 2)
        #expect(await expiryFixture.policyCutoverState.current() != nil)
    }

    @Test func sealedExpiryHandoffAllowsOnlyBoundedOrdinaryRecovery()
        async throws {
        for finishWithSameCommand in [true, false] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let expired = try coordinatorOutboxEntry(
                index: finishWithSameCommand ? 317 : 318,
                createdAt: fixture.clock.now.addingTimeInterval(-86_400),
                generation: 1
            )
            let expiredRecord = try coordinatorDeliveryRecord(
                matching: expired,
                state: .pending
            )
            fixture.delivery.install(expiredRecord)
            let coordinator = fixture.coordinator()

            #expect(
                try await coordinator.clearHistoryPolicy()
                    == .pendingLocalRecovery
            )
            #expect(fixture.policy.currentState?.revision == 2)
            #expect(await fixture.policyCutoverState.current() != nil)
            let sealedObservation = await fixture.policyCutoverState
                .expiredDeliveryAbandonmentObservation(
                    ownerIdentity: fixture.ownerIdentity
                )
            #expect(sealedObservation?.record == expiredRecord)
            #expect(
                sealedObservation?.belongs(
                    to: fixture.deliveryStore.storeIdentity
                ) == true
            )
            let acceptedLoads = fixture.accepted.loadCount
            let policyReplaces = fixture.policy.replaceCount
            fixture.clock.rollBack(seconds: 86_401)

            #expect(try await coordinator.recoverAcceptedHistory() == nil)
            #expect(fixture.delivery.currentRecord == nil)
            #expect(fixture.delivery.removeCount == 1)
            #expect(fixture.accepted.loadCount == acceptedLoads)
            #expect(fixture.policy.replaceCount == policyReplaces)
            #expect(fixture.policy.currentState?.revision == 2)
            #expect(await fixture.policyCutoverState.current() != nil)

            let disposition = if finishWithSameCommand {
                try await coordinator.clearHistoryPolicy()
            } else {
                try await coordinator.recoverHistoryPolicyCleanup()
            }
            #expect(disposition == .complete)
            #expect(fixture.policy.currentState?.revision == 2)
            #expect(fixture.policy.replaceCount == policyReplaces)
            #expect(await fixture.policyCutoverState.current() == nil)
        }
    }

    @Test func nonExpiredCutoverPhasesNeverOpenOrdinaryRecovery()
        async throws {
        let active = CoordinatorFixture()
        active.policy.install(.baseline)
        let activeEntry = try coordinatorOutboxEntry(
            index: 319,
            createdAt: active.clock.now,
            generation: 1
        )
        active.delivery.install(
            try coordinatorDeliveryRecord(
                matching: activeEntry,
                state: .pending
            )
        )
        active.delivery.failReplace(
            onCall: active.delivery.replaceCount + 1,
            with: .compareAndSwapFailed,
            commitBeforeThrowing: false
        )
        let activeCoordinator = active.coordinator()
        #expect(
            try await activeCoordinator.clearHistoryPolicy()
                == .pendingLocalRecovery
        )
        let activeLoads = active.delivery.loadCount
        #expect(
            try await activeCoordinator.recoverAcceptedHistory()
                == .pendingLocalRecovery
        )
        #expect(active.delivery.loadCount == activeLoads)
        #expect(active.delivery.currentRecord?.historyWrite?.state == .pending)
        let activeExpiry = await active.policyCutoverState
            .expiredDeliveryAbandonmentObservation(
                ownerIdentity: active.ownerIdentity
            )
        #expect(activeExpiry == nil)

        let future = CoordinatorFixture()
        future.policy.install(.baseline)
        let futureEntry = try coordinatorOutboxEntry(
            index: 320,
            createdAt: future.clock.now,
            generation: 3
        )
        future.delivery.install(
            try coordinatorDeliveryRecord(
                matching: futureEntry,
                state: .pending
            )
        )
        let futureCoordinator = future.coordinator()
        #expect(
            try await futureCoordinator.clearHistoryPolicy()
                == .pendingLocalRecovery
        )
        let futureLoads = future.delivery.loadCount
        #expect(
            try await futureCoordinator.recoverAcceptedHistory()
                == .pendingLocalRecovery
        )
        #expect(future.delivery.loadCount == futureLoads)
        #expect(future.delivery.currentRecord?.historyWrite?.state == .pending)
        let futureExpiry = await future.policyCutoverState
            .expiredDeliveryAbandonmentObservation(
                ownerIdentity: future.ownerIdentity
            )
        #expect(futureExpiry == nil)

        let rollback = CoordinatorFixture()
        rollback.policy.install(.baseline)
        let rollbackEntry = try coordinatorOutboxEntry(
            index: 321,
            createdAt: rollback.clock.now.addingTimeInterval(1),
            generation: 1
        )
        rollback.delivery.install(
            try coordinatorDeliveryRecord(
                matching: rollbackEntry,
                state: .pending
            )
        )
        let rollbackCoordinator = rollback.coordinator()
        #expect(
            try await rollbackCoordinator.clearHistoryPolicy()
                == .pendingLocalRecovery
        )
        let rollbackLoads = rollback.delivery.loadCount
        #expect(
            try await rollbackCoordinator.recoverAcceptedHistory()
                == .pendingLocalRecovery
        )
        #expect(rollback.delivery.loadCount == rollbackLoads)
        #expect(
            rollback.delivery.currentRecord?.historyWrite?.state == .pending
        )
        let rollbackExpiry = await rollback.policyCutoverState
            .expiredDeliveryAbandonmentObservation(
                ownerIdentity: rollback.ownerIdentity
            )
        #expect(rollbackExpiry == nil)
    }

    @Test func foreignSealedExpiryObservationFailsBeforeDeliveryIO()
        async throws {
        let source = CoordinatorFixture()
        let expired = try coordinatorOutboxEntry(
            index: 322,
            createdAt: source.clock.now.addingTimeInterval(-86_400),
            generation: 1
        )
        let record = try coordinatorDeliveryRecord(
            matching: expired,
            state: .pending
        )
        source.delivery.install(record)
        let observationResult = try await source.deliveryStore
            .observeExpiredHistoryAbandonment(
                expected: IOSAcceptedOutputDeliveryExpectation(record: record)
            )
        guard case .observed(let foreignObservation) = observationResult else {
            Issue.record("Expected sealed source observation")
            return
        }

        let destination = CoordinatorFixture()
        #expect(
            foreignObservation.belongs(
                to: source.deliveryStore.storeIdentity
            )
        )
        #expect(
            !foreignObservation.belongs(
                to: destination.deliveryStore.storeIdentity
            )
        )
        let policy = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: false,
            policyGeneration: 2
        )
        destination.policy.install(policy)
        let policyReceipt = try await destination.policyStore.confirm(
            expected: IOSHistoryPolicyExpectation(state: policy)
        )
        destination.delivery.install(record)
        await destination.policyCutoverState.store(
            IOSHistoryPolicyCutoverWork(
                ownerIdentity: destination.ownerIdentity,
                command: .clear,
                phase: .awaitingExpiredDeliveryAbandonment(
                    policyReceipt,
                    foreignObservation
                )
            )
        )
        let deliveryLoads = destination.delivery.loadCount

        #expect(
            try await destination.coordinator().recoverAcceptedHistory()
                == .pendingLocalRecovery
        )
        #expect(destination.delivery.loadCount == deliveryLoads)
        #expect(destination.delivery.removeCount == 0)
        #expect(destination.delivery.currentRecord == record)
        #expect(destination.policy.currentState == policy)
    }

    @Test func repositoryConflictAfterPolicyCommitKeepsTheCutoverBoundary()
        async throws {
        let preBoundary = CoordinatorFixture()
        preBoundary.policy.install(.baseline)
        preBoundary.repositoryIdentityState.markConflicted()
        await #expect(
            throws:
                IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await preBoundary.coordinator().clearHistoryPolicy()
        }
        #expect(preBoundary.policy.currentState == .baseline)
        #expect(await preBoundary.policyCutoverState.current() == nil)

        let postBoundary = CoordinatorFixture()
        postBoundary.policy.install(.baseline)
        let stale = try coordinatorHistoryEntry(
            index: 315,
            createdAt: postBoundary.clock.now,
            generation: 1
        )
        postBoundary.accepted.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 1,
                entries: [stale]
            )
        )
        let blocker = CoordinatorBoundaryBlocker()
        postBoundary.accepted.replaceBlocker = blocker
        let coordinator = postBoundary.coordinator()
        let clear = Task { try await coordinator.clearHistoryPolicy() }
        #expect(blocker.waitUntilBlocked())
        postBoundary.repositoryIdentityState.markConflicted()
        blocker.open()

        #expect(try await clear.value == .pendingLocalRecovery)
        #expect(postBoundary.policy.currentState?.revision == 2)
        #expect(await postBoundary.policyCutoverState.current() != nil)

        #expect(
            try await coordinator.clearHistoryPolicy()
                == .pendingLocalRecovery
        )
        #expect(postBoundary.policy.currentState?.revision == 2)
        #expect(await postBoundary.policyCutoverState.current() != nil)
    }

    @Test func recoveryRepositoryConflictRemainsTypedAfterConfirmation()
        async throws {
        let fixture = CoordinatorFixture()
        let policy = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: false,
            policyGeneration: 2
        )
        fixture.policy.install(policy)
        let stale = try coordinatorHistoryEntry(
            index: 316,
            createdAt: fixture.clock.now,
            generation: 1
        )
        fixture.accepted.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 1,
                entries: [stale]
            )
        )
        let blocker = CoordinatorBoundaryBlocker()
        fixture.accepted.replaceBlocker = blocker
        let recovery = Task {
            try await fixture.coordinator().recoverHistoryPolicyCleanup()
        }
        #expect(blocker.waitUntilBlocked())
        fixture.repositoryIdentityState.markConflicted()
        blocker.open()

        await #expect(
            throws:
                IOSAcceptedHistoryCoordinatorError.repositoryIdentityConflict
        ) {
            _ = try await recovery.value
        }
        #expect(fixture.policy.currentState == policy)
    }

    @Test func uncertainOutboxRetirementNeverSkipsTheHead() async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let now = fixture.clock.now
        let first = try coordinatorOutboxEntry(
            index: 306,
            createdAt: now.addingTimeInterval(-2),
            generation: 1
        )
        let second = try coordinatorOutboxEntry(
            index: 307,
            createdAt: now.addingTimeInterval(-1),
            generation: 1
        )
        fixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [first, second]
            )
        )
        fixture.outbox.failReplace(
            onCall: fixture.outbox.replaceCount + 2,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        let coordinator = fixture.coordinator()

        #expect(
            try await coordinator.clearHistoryPolicy()
                == .pendingLocalRecovery
        )
        #expect(fixture.outbox.currentEnvelope?.entries == [first, second])

        #expect(
            try await coordinator.recoverHistoryPolicyCleanup()
                == .pendingLocalRecovery
        )
        #expect(fixture.outbox.currentEnvelope?.entries == [second])

        #expect(
            try await coordinator.recoverHistoryPolicyCleanup()
                == .pendingLocalRecovery
        )
        #expect(fixture.outbox.currentEnvelope?.entries.isEmpty == true)
    }

    @Test func standaloneDeliveryCleanupCancelsOnlyStaleUnresolvedMarkers()
        async throws {
        let staleFixture = CoordinatorFixture()
        staleFixture.policy.install(.baseline)
        let staleEntry = try coordinatorOutboxEntry(
            index: 308,
            createdAt: staleFixture.clock.now,
            generation: 1
        )
        staleFixture.delivery.install(
            try coordinatorDeliveryRecord(
                matching: staleEntry,
                state: .pendingReplacement
            )
        )
        #expect(
            try await staleFixture.coordinator().clearHistoryPolicy()
                == .complete
        )
        #expect(
            staleFixture.delivery.currentRecord?.historyWrite?.state
                == .cancelled
        )

        let currentFixture = CoordinatorFixture()
        currentFixture.policy.install(
            try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: true,
                policyGeneration: 2
            )
        )
        let currentEntry = try coordinatorOutboxEntry(
            index: 309,
            createdAt: currentFixture.clock.now,
            generation: 2
        )
        let currentRecord = try coordinatorDeliveryRecord(
            matching: currentEntry,
            state: .pending
        )
        currentFixture.delivery.install(currentRecord)
        #expect(
            try await currentFixture.coordinator()
                .recoverHistoryPolicyCleanup() == .complete
        )
        #expect(currentFixture.delivery.currentRecord == currentRecord)

        let terminalFixture = CoordinatorFixture()
        terminalFixture.policy.install(
            try IOSHistoryPolicyState(
                revision: 2,
                historyEnabled: false,
                policyGeneration: 2
            )
        )
        let terminalEntry = try coordinatorOutboxEntry(
            index: 310,
            createdAt: terminalFixture.clock.now,
            generation: 1
        )
        let terminalRecord = try coordinatorDeliveryRecord(
            matching: terminalEntry,
            state: .committed
        )
        terminalFixture.delivery.install(terminalRecord)
        #expect(
            try await terminalFixture.coordinator()
                .recoverHistoryPolicyCleanup() == .complete
        )
        #expect(terminalFixture.delivery.currentRecord == terminalRecord)
    }

    @Test func retainedHistoryOperationsBlockCutoverBeforePolicyIO()
        async throws {
        let acceptanceFixture = CoordinatorFixture()
        acceptanceFixture.policy.install(.baseline)
        let acceptanceCoordinator = acceptanceFixture.coordinator()
        let preparation = try await coordinatorPreparation(
            using: acceptanceCoordinator
        )
        let accepted = try await acceptanceFixture.deliveryStore.accept(
            preparation
        )
        await acceptanceFixture.acceptanceState.store(
            .fresh(preparation, .deliveryAccepted(accepted))
        )
        let acceptancePolicyLoads = acceptanceFixture.policy.loadCount
        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            _ = try await acceptanceCoordinator.clearHistoryPolicy()
        }
        #expect(
            acceptanceFixture.policy.loadCount == acceptancePolicyLoads
        )

        let replacementFixture = CoordinatorFixture()
        replacementFixture.policy.install(.baseline)
        let replacementCoordinator = replacementFixture.coordinator()
        let replacementPreparation = try await coordinatorPreparation(
            using: replacementCoordinator
        )
        await replacementFixture.pendingReplacementState.store(
            IOSAcceptedHistoryPendingReplacementWork(
                ownerIdentity: replacementFixture.ownerIdentity,
                preparation: replacementPreparation,
                phase: .observingCurrentDelivery
            )
        )
        let replacementPolicyLoads = replacementFixture.policy.loadCount
        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            _ = try await replacementCoordinator.clearHistoryPolicy()
        }
        #expect(
            replacementFixture.policy.loadCount == replacementPolicyLoads
        )

        let workerFixture = CoordinatorFixture()
        workerFixture.policy.install(.baseline)
        let workerHead = try coordinatorOutboxEntry(
            index: 311,
            createdAt: workerFixture.clock.now
        )
        workerFixture.outbox.install(
            try IOSAcceptedHistoryOutboxEnvelope(
                revision: 1,
                entries: [workerHead]
            )
        )
        let observation = try #require(
            try await workerFixture.outboxStore.observeHead()
        )
        await workerFixture.outboxWorkerState.store(
            IOSAcceptedHistoryOutboxWorkerWork(
                ownerIdentity: workerFixture.ownerIdentity,
                phase: .headObserved(observation)
            )
        )
        let workerPolicyLoads = workerFixture.policy.loadCount
        await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
            _ = try await workerFixture.coordinator().clearHistoryPolicy()
        }
        #expect(workerFixture.policy.loadCount == workerPolicyLoads)
    }

    @Test func retainedCutoverBlocksOtherHistoryWorkAndIsRedacted()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let stale = try coordinatorHistoryEntry(
            index: 312,
            createdAt: fixture.clock.now,
            generation: 1
        )
        fixture.accepted.install(
            try IOSAcceptedHistoryEnvelope(
                revision: 1,
                entries: [stale]
            )
        )
        fixture.accepted.failReplace(
            onCall: fixture.accepted.replaceCount + 1,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        let coordinator = fixture.coordinator()
        #expect(
            try await coordinator.clearHistoryPolicy()
                == .pendingLocalRecovery
        )
        let retained = try #require(await fixture.policyCutoverState.current())
        #expect(String(describing: retained).contains("redacted"))
        #expect(retained.customMirror.children.isEmpty)
        #expect(
            String(describing: retained.phase)
                == "IOSHistoryPolicyCutoverPhase(redacted)"
        )

        await #expect(throws: IOSAcceptedOutputDeliveryError.commitUncertain) {
            _ = try await coordinator.capture(
                transcriptionModel: "model",
                transcriptionLanguageCode: nil,
                durationMilliseconds: nil
            )
        }
        #expect(
            try await coordinator.recoverAcceptedHistory()
                == .pendingLocalRecovery
        )
        let outboxLoads = fixture.outbox.loadCount
        #expect(
            try await coordinator.recoverAcceptedHistoryOutbox()
                == .pendingLocalRecovery
        )
        #expect(fixture.outbox.loadCount == outboxLoads)
        #expect(
            String(describing:
                IOSHistoryPolicyCleanupDisposition.pendingLocalRecovery)
                == "IOSHistoryPolicyCleanupDisposition(redacted)"
        )
        #expect(
            IOSHistoryPolicyCleanupDisposition.pendingLocalRecovery
                .customMirror.children.isEmpty
        )
    }

    @Test func policyAPICancellationBeforeLeasePerformsZeroRepositoryIO()
        async throws {
        for operation in CoordinatorPolicyAPIOperation.allCases {
            let probe = CoordinatorGateProbe()
            let gate = IOSPersistenceOperationGate { event in
                probe.record(event)
            }
            let fixture = CoordinatorFixture(gate: gate)
            fixture.policy.install(.baseline)
            let blocker = CoordinatorAsyncOperationBlocker()
            let active = Task {
                try await gate.perform { await blocker.wait() }
            }
            await blocker.waitUntilSuspended()
            let coordinator = fixture.coordinator()
            let cancelled = Task {
                try await operation.invoke(on: coordinator)
            }
            #expect(probe.waitUntilEnqueued())
            cancelled.cancel()
            await blocker.open()

            try await active.value
            await #expect(
                throws:
                    IOSAcceptedHistoryCoordinatorError
                        .cancelledBeforeOperation
            ) {
                _ = try await cancelled.value
            }
            #expect(fixture.policy.loadCount == 0)
            #expect(fixture.policy.replaceCount == 0)
            #expect(fixture.accepted.loadCount == 0)
            #expect(fixture.outbox.loadCount == 0)
            #expect(fixture.delivery.loadCount == 0)
            #expect(await fixture.policyCutoverState.current() == nil)
        }
    }

    @Test func cancellationAfterPolicyAPILeaseCompletesExactlyOnce()
        async throws {
        for operation in CoordinatorPolicyAPIOperation.allCases {
            let probe = CoordinatorGateProbe()
            let gate = IOSPersistenceOperationGate { event in
                probe.record(event)
            }
            let fixture = CoordinatorFixture(gate: gate)
            fixture.policy.install(.baseline)
            let blocker = CoordinatorBoundaryBlocker()
            fixture.policy.loadBlocker = blocker
            let coordinator = fixture.coordinator()
            let task = Task { try await operation.invoke(on: coordinator) }
            #expect(blocker.waitUntilBlocked())
            task.cancel()
            blocker.open()

            #expect(try await task.value == .complete)
            #expect(
                fixture.policy.currentState?.revision
                    == operation.expectedRevision
            )
            #expect(
                fixture.policy.currentState?.historyEnabled
                    == operation.expectedEnabled
            )
            #expect(
                fixture.policy.loadCount
                    == operation.expectedPolicyLoadCount
            )
            #expect(
                fixture.policy.replaceCount
                    == operation.expectedPolicyReplaceCount
            )
            #expect(fixture.accepted.loadCount == 1)
            #expect(fixture.outbox.loadCount == 1)
            #expect(fixture.delivery.loadCount == 1)
            #expect(probe.grantedCount == 1)
            #expect(probe.releasedCount == 1)
            #expect(await fixture.policyCutoverState.current() == nil)
        }
    }

    @Test func policyAPIsRejectReentrancyBeforeRepositoryIO() async throws {
        for operation in CoordinatorPolicyAPIOperation.allCases {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let coordinator = fixture.coordinator()

            await #expect(
                throws: IOSAcceptedHistoryCoordinatorError.reentrantOperation
            ) {
                _ = try await fixture.gate.perform {
                    try await operation.invoke(on: coordinator)
                }
            }
            #expect(fixture.policy.loadCount == 0)
            #expect(fixture.policy.replaceCount == 0)
            #expect(fixture.accepted.loadCount == 0)
            #expect(fixture.outbox.loadCount == 0)
            #expect(fixture.delivery.loadCount == 0)
            #expect(await fixture.policyCutoverState.current() == nil)
        }
    }

    @Test func policyMutationCASSupersessionRequiresAFreshCommand()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let winner = try IOSHistoryPolicyState(
            revision: 2,
            historyEnabled: false,
            policyGeneration: 2
        )
        fixture.policy.raceReplace(
            onCall: fixture.policy.replaceCount + 2,
            with: winner
        )
        let coordinator = fixture.coordinator()

        await #expect(throws: IOSHistoryPolicyError.compareAndSwapFailed) {
            _ = try await coordinator.clearHistoryPolicy()
        }
        #expect(fixture.policy.currentState == winner)
        #expect(fixture.accepted.loadCount == 0)
        #expect(fixture.outbox.loadCount == 0)
        #expect(fixture.delivery.loadCount == 0)
        #expect(await fixture.policyCutoverState.current() == nil)
        let policyLoads = fixture.policy.loadCount
        let freshClear = try IOSHistoryPolicyState(
            revision: 3,
            historyEnabled: false,
            policyGeneration: 3
        )

        #expect(try await coordinator.clearHistoryPolicy() == .complete)
        #expect(fixture.policy.loadCount == policyLoads + 3)
        #expect(fixture.policy.currentState == freshClear)
    }

    @Test func everyDeliveryRetainedWorkFamilyBlocksPolicyBeforeIO()
        async throws {
        let transition = CoordinatorFixture()
        transition.policy.install(.baseline)
        let transitionCapabilities = try await coordinatorPendingCapabilities(
            fixture: transition
        )
        let invalidation = try await transition.policyStore.clear(
            using: transitionCapabilities.policyReceipt
        )
        transition.delivery.failReplace(
            onCall: transition.delivery.replaceCount + 1,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.commitUncertain
        ) {
            _ = try await transition.deliveryStore.cancelHistoryWrite(
                authorization: transitionCapabilities.authorization,
                policyInvalidationReceipt: invalidation
            )
        }
        await expectPolicyCutoverBlockedBeforeIO(transition)

        let replacement = CoordinatorFixture()
        replacement.policy.install(.baseline)
        let replacementCapabilities = try await coordinatorPendingCapabilities(
            fixture: replacement
        )
        let replacementPreparation = try await coordinatorPreparation(
            using: replacement.coordinator(),
            text: "uncertain replacement"
        )
        replacement.delivery.failReplace(
            onCall: replacement.delivery.replaceCount + 1,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.commitUncertain
        ) {
            _ = try await replacement.deliveryStore
                .replacePendingHistoryForTesting(
                    with: replacementPreparation,
                    authorization: replacementCapabilities.authorization,
                    ownershipProof: replacementCapabilities.ownershipProof
                )
        }
        await expectPolicyCutoverBlockedBeforeIO(replacement)

        let pendingClear = CoordinatorFixture()
        pendingClear.policy.install(.baseline)
        let clearCapabilities = try await coordinatorPendingCapabilities(
            fixture: pendingClear
        )
        pendingClear.delivery.failReplace(
            onCall: pendingClear.delivery.replaceCount + 1,
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.commitUncertain
        ) {
            _ = try await pendingClear.deliveryStore.clearPendingHistory(
                authorization: clearCapabilities.authorization,
                ownershipProof: clearCapabilities.ownershipProof
            )
        }
        await expectPolicyCutoverBlockedBeforeIO(pendingClear)

        let acceptance = CoordinatorFixture()
        acceptance.policy.install(.baseline)
        let acceptancePreparation = try await coordinatorPreparation(
            using: acceptance.coordinator(),
            text: "uncertain acceptance"
        )
        acceptance.delivery.failNextCreate(
            with: .commitUncertain,
            commitBeforeThrowing: false
        )
        await #expect(
            throws: IOSAcceptedOutputDeliveryError.commitUncertain
        ) {
            _ = try await acceptance.deliveryStore.accept(
                acceptancePreparation
            )
        }
        await expectPolicyCutoverBlockedBeforeIO(acceptance)

        let transfer = CoordinatorFixture()
        transfer.policy.install(.baseline)
        let transferCapabilities = try await coordinatorPendingCapabilities(
            fixture: transfer
        )
        _ = try await transfer.deliveryStore.reservePendingHistoryTransfer(
            authorization: transferCapabilities.authorization,
            policyReceipt: transferCapabilities.policyReceipt
        )
        await expectPolicyCutoverBlockedBeforeIO(transfer)

        let bridge = CoordinatorFixture()
        bridge.policy.install(.baseline)
        let bridgeCapabilities = try await coordinatorPendingCapabilities(
            fixture: bridge
        )
        _ = try await bridge.deliveryStore.reserveBridgePublication(
            authorization: bridgeCapabilities.authorization
        )
        await expectPolicyCutoverBlockedBeforeIO(bridge)
    }

    @Test func cancellationUncertaintyRecoversAfterProcessLossWithoutNPlusTwo()
        async throws {
        for commitWasVisible in [true, false] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let entry = try coordinatorOutboxEntry(
                index: commitWasVisible ? 323 : 324,
                createdAt: fixture.clock.now.addingTimeInterval(-60),
                generation: 1
            )
            fixture.delivery.install(
                try coordinatorDeliveryRecord(
                    matching: entry,
                    state: .pending
                )
            )
            fixture.delivery.failReplace(
                onCall: fixture.delivery.replaceCount + 2,
                with: .commitUncertain,
                commitBeforeThrowing: commitWasVisible
            )
            let coordinator = fixture.coordinator()

            #expect(
                try await coordinator.clearHistoryPolicy()
                    == .pendingLocalRecovery
            )
            #expect(fixture.policy.currentState?.revision == 2)
            let work = try #require(
                await fixture.policyCutoverState.current()
            )
            guard case .cancellingStandaloneDelivery(
                let policyReceipt,
                let authorization
            ) = work.phase else {
                Issue.record("Expected exact retained cancellation phase")
                continue
            }
            #expect(policyReceipt.state.policyGeneration == 2)
            #expect(
                authorization.record.historyWrite?.policyGeneration == 1
            )
            #expect(
                authorization.record.historyWrite?.state.isPendingDecision
                    == true
            )

            let relaunched = fixture.relaunchedCoordinator()
            #expect(
                try await relaunched.recoverHistoryPolicyCleanup() == .complete
            )
            #expect(fixture.policy.currentState?.revision == 2)
            #expect(
                fixture.delivery.currentRecord?.historyWrite?.state
                    == .cancelled
            )
        }
    }

    @Test func sealedExpiryRemovalUncertaintyRecoversAfterProcessLoss()
        async throws {
        for commitWasVisible in [true, false] {
            let fixture = CoordinatorFixture()
            fixture.policy.install(.baseline)
            let entry = try coordinatorOutboxEntry(
                index: commitWasVisible ? 325 : 326,
                createdAt: fixture.clock.now.addingTimeInterval(-86_400),
                generation: 1
            )
            fixture.delivery.install(
                try coordinatorDeliveryRecord(
                    matching: entry,
                    state: .pending
                )
            )
            let coordinator = fixture.coordinator()
            #expect(
                try await coordinator.clearHistoryPolicy()
                    == .pendingLocalRecovery
            )
            let sealed = try #require(
                await fixture.policyCutoverState
                    .expiredDeliveryAbandonmentObservation(
                        ownerIdentity: fixture.ownerIdentity
                    )
            )
            fixture.delivery.failNextRemove(
                with: .removalCommitUncertain,
                commitBeforeThrowing: commitWasVisible
            )

            #expect(
                try await coordinator.recoverAcceptedHistory()
                    == .pendingLocalRecovery
            )
            let retained = try #require(await fixture.acceptanceState.current())
            guard case .relaunched(.removingExpired(let authorization))
                    = retained else {
                Issue.record("Expected exact retained expired-removal phase")
                continue
            }
            #expect(sealed.provesLineage(of: authorization))
            #expect(fixture.policy.currentState?.revision == 2)

            let relaunched = fixture.relaunchedCoordinator()
            let firstCleanup = try await relaunched
                .recoverHistoryPolicyCleanup()
            if commitWasVisible {
                #expect(firstCleanup == .complete)
            } else {
                #expect(firstCleanup == .pendingLocalRecovery)
                #expect(try await relaunched.recoverAcceptedHistory() == nil)
                #expect(
                    try await relaunched.recoverHistoryPolicyCleanup()
                        == .complete
                )
            }
            #expect(fixture.delivery.currentRecord == nil)
            #expect(fixture.policy.currentState?.revision == 2)
        }
    }

    @Test func staleMarkerCancellationPreservesEveryNonHistoryByte()
        async throws {
        let fixture = CoordinatorFixture()
        fixture.policy.install(.baseline)
        let cancellationTime = fixture.clock.now
        let entry = try coordinatorOutboxEntry(
            index: 327,
            createdAt: cancellationTime.addingTimeInterval(-60),
            generation: 1,
            acceptedText: "preserved exact 🎙️ text\nsecond line"
        )
        let original = try coordinatorDeliveryRecord(
            matching: entry,
            state: .pending,
            acceptedText: entry.acceptedText
        )
        fixture.delivery.install(original)

        #expect(
            try await fixture.coordinator().clearHistoryPolicy() == .complete
        )
        let cancelled = try #require(fixture.delivery.currentRecord)
        let originalMarker = try #require(original.historyWrite)
        let cancelledMarker = try IOSAcceptedOutputHistoryWrite(
            state: .cancelled,
            policyGeneration: originalMarker.policyGeneration,
            transcriptionModel: originalMarker.transcriptionModel,
            transcriptionLanguageCode:
                originalMarker.transcriptionLanguageCode,
            durationMilliseconds: originalMarker.durationMilliseconds
        )
        let expected = try IOSAcceptedOutputDeliveryRecord(
            revision: original.revision + 1,
            deliveryID: original.deliveryID,
            sessionID: original.sessionID,
            attemptID: original.attemptID,
            transcriptID: original.transcriptID,
            acceptedText: original.acceptedText,
            outputIntent: original.outputIntent,
            createdAt: original.createdAt,
            updatedAt: cancellationTime,
            expiresAt: original.expiresAt,
            deliveryState: original.deliveryState,
            automaticInsertionPreferenceEnabled:
                original.automaticInsertionPreferenceEnabled,
            keepLatestResult: original.keepLatestResult,
            publicationGeneration: original.publicationGeneration,
            historyWrite: cancelledMarker
        )

        #expect(cancelled == expected)
        #expect(cancelled.acceptedText == original.acceptedText)
        #expect(cancelled.deliveryState == original.deliveryState)
        #expect(
            cancelled.publicationGeneration
                == original.publicationGeneration
        )
        #expect(cancelled.keepLatestResult == original.keepLatestResult)
        #expect(cancelled.updatedAt != original.updatedAt)
        #expect(cancelled.historyWrite?.state == .cancelled)
        #expect(fixture.policy.currentState?.revision == 2)
    }
}

private enum CoordinatorPolicyAPIOperation: CaseIterable, Sendable {
    case clear
    case disable
    case recover

    var expectedRevision: Int64 {
        switch self {
        case .clear, .disable: 2
        case .recover: 1
        }
    }

    var expectedEnabled: Bool {
        switch self {
        case .clear, .recover: true
        case .disable: false
        }
    }

    var expectedPolicyLoadCount: Int {
        switch self {
        case .clear, .disable: 3
        case .recover: 2
        }
    }

    var expectedPolicyReplaceCount: Int {
        switch self {
        case .clear, .disable: 2
        case .recover: 1
        }
    }

    func invoke(
        on coordinator: IOSAcceptedHistoryCoordinator
    ) async throws -> IOSHistoryPolicyCleanupDisposition {
        switch self {
        case .clear:
            return try await coordinator.clearHistoryPolicy()
        case .disable:
            return try await coordinator.setHistoryEnabled(false)
        case .recover:
            return try await coordinator.recoverHistoryPolicyCleanup()
        }
    }
}

private struct CoordinatorPendingHistoryCapabilities {
    let authorization: IOSAcceptedOutputDeliveryAuthorization
    let policyReceipt: IOSHistoryPolicyReceipt
    let ownershipProof: IOSAcceptedOutputHistoryOwnershipProof
}

private func coordinatorPendingCapabilities(
    fixture: CoordinatorFixture
) async throws -> CoordinatorPendingHistoryCapabilities {
    let preparation = try await coordinatorPreparation(
        using: fixture.coordinator(),
        text: "retained delivery work"
    )
    let accepted = try await fixture.deliveryStore.accept(preparation)
    let authorization = try await fixture.deliveryStore
        .authorizePendingHistoryWrite(
            expected: IOSAcceptedOutputDeliveryExpectation(record: accepted)
        )
    let policyState = try #require(try await fixture.policyStore.load())
    let policyReceipt = try await fixture.policyStore.confirm(
        expected: IOSHistoryPolicyExpectation(state: policyState)
    )
    let rowReceipt = try await fixture.acceptedHistoryStore.decideUpsert(
        delivery: authorization,
        policy: policyReceipt
    )
    return CoordinatorPendingHistoryCapabilities(
        authorization: authorization,
        policyReceipt: policyReceipt,
        ownershipProof: IOSAcceptedOutputHistoryOwnershipProof(
            retainedRowReceipt: rowReceipt
        )
    )
}

private func expectPolicyCutoverBlockedBeforeIO(
    _ fixture: CoordinatorFixture
) async {
    let counts = (
        fixture.policy.loadCount,
        fixture.policy.replaceCount,
        fixture.accepted.loadCount,
        fixture.outbox.loadCount,
        fixture.delivery.loadCount
    )
    await #expect(throws: IOSHistoryPolicyError.commitUncertain) {
        _ = try await fixture.coordinator().clearHistoryPolicy()
    }
    #expect(fixture.policy.loadCount == counts.0)
    #expect(fixture.policy.replaceCount == counts.1)
    #expect(fixture.accepted.loadCount == counts.2)
    #expect(fixture.outbox.loadCount == counts.3)
    #expect(fixture.delivery.loadCount == counts.4)
    #expect(await fixture.policyCutoverState.current() == nil)
}

private func coordinatorPreparation(
    using coordinator: IOSAcceptedHistoryCoordinator,
    text: String = "accepted text"
) async throws -> IOSAcceptedOutputDeliveryPreparation {
    let capture = try await coordinator.capture(
        transcriptionModel: "whisper-1",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250
    )
    return try IOSAcceptedOutputDeliveryPreparation(
        deliveryID: UUID(),
        sessionID: UUID(),
        attemptID: UUID(),
        transcriptID: UUID(),
        rawAcceptedText: text,
        outputIntent: .standard,
        automaticInsertionPreferenceEnabled: true,
        keepLatestResult: true,
        historyCapture: capture
    )
}

private func rebuiltPreparation(
    using coordinator: IOSAcceptedHistoryCoordinator,
    matching preparation: IOSAcceptedOutputDeliveryPreparation
) async throws -> IOSAcceptedOutputDeliveryPreparation {
    let marker = preparation.historyWrite
    let capture = try await coordinator.capture(
        transcriptionModel: marker?.transcriptionModel ?? "whisper-1",
        transcriptionLanguageCode: marker?.transcriptionLanguageCode,
        durationMilliseconds: marker?.durationMilliseconds
    )
    return try IOSAcceptedOutputDeliveryPreparation(
        deliveryID: preparation.deliveryID,
        sessionID: preparation.sessionID,
        attemptID: preparation.attemptID,
        transcriptID: preparation.transcriptID,
        rawAcceptedText: preparation.acceptedText,
        outputIntent: preparation.outputIntent,
        automaticInsertionPreferenceEnabled:
            preparation.automaticInsertionPreferenceEnabled,
        keepLatestResult: preparation.keepLatestResult,
        historyCapture: capture
    )
}

private final class CoordinatorFixture: @unchecked Sendable {
    let events = CoordinatorEventRecorder()
    let policy: CoordinatorPolicyJournal
    let accepted: CoordinatorAcceptedJournal
    let outbox: CoordinatorOutboxJournal
    let delivery: CoordinatorDeliveryJournal
    let gate: IOSPersistenceOperationGate
    let recoveryState = IOSAcceptedHistoryBaselineRecoveryState()
    let acceptanceState = IOSAcceptedHistoryAcceptanceOperationState()
    let pendingReplacementState =
        IOSAcceptedHistoryPendingReplacementOperationState()
    let outboxWorkerState = IOSAcceptedHistoryOutboxWorkerOperationState()
    let policyCutoverState = IOSHistoryPolicyCutoverOperationState()
    let ownerIdentity = IOSAcceptedHistoryCoordinatorOwnerIdentity()
    let clock: CoordinatorClock
    let policyStore: IOSHistoryPolicyStore
    let acceptedHistoryStore: IOSAcceptedHistoryStore
    let failedHistoryFileSystem = FailedHistoryFakeFileSystem()
    let failedHistoryStore: IOSFailedHistoryStore
    let outboxStore: IOSAcceptedHistoryOutboxStore
    let deliveryStore: IOSAcceptedOutputDeliveryStore
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
        let clock = CoordinatorClock()
        let deliveryStoreIdentity = IOSAcceptedOutputDeliveryStoreIdentity()
        let outboxStoreIdentity = IOSAcceptedHistoryOutboxStoreIdentity()
        self.gate = gate
        self.clock = clock
        self.repositoryIdentityState = repositoryIdentityState
        self.repositoryRegistration = repositoryRegistration
        policy = CoordinatorPolicyJournal(events: events)
        accepted = CoordinatorAcceptedJournal(events: events)
        outbox = CoordinatorOutboxJournal(events: events)
        delivery = CoordinatorDeliveryJournal(events: events)
        policyStore = IOSHistoryPolicyStore(
            journal: policy,
            capabilityOwnerIdentity: ownerIdentity
        )
        acceptedHistoryStore = IOSAcceptedHistoryStore(
            journal: accepted,
            now: { clock.now },
            capabilityOwnerIdentity: ownerIdentity
        )
        failedHistoryStore = IOSFailedHistoryStore(
            journal: FoundationIOSFailedHistoryJournalRepository(
                fileSystem: failedHistoryFileSystem
            ),
            capabilityOwnerIdentity: ownerIdentity,
            now: { clock.now }
        )
        outboxStore = IOSAcceptedHistoryOutboxStore(
            journal: outbox,
            now: { clock.now },
            deliveryStoreIdentity: deliveryStoreIdentity,
            storeIdentity: outboxStoreIdentity,
            capabilityOwnerIdentity: ownerIdentity
        )
        deliveryStore = IOSAcceptedOutputDeliveryStore(
            journal: delivery,
            now: { clock.now },
            monotonicNowNanoseconds: { clock.uptimeNanoseconds },
            storeIdentity: deliveryStoreIdentity,
            outboxStoreIdentity: outboxStoreIdentity,
            capabilityOwnerIdentity: ownerIdentity
        )
    }

    func coordinator() -> IOSAcceptedHistoryCoordinator {
        IOSAcceptedHistoryCoordinator(
            policyStore: policyStore,
            acceptedHistoryStore: acceptedHistoryStore,
            failedHistoryStore: failedHistoryStore,
            outboxStore: outboxStore,
            deliveryStore: deliveryStore,
            operationGate: gate,
            baselineRecoveryState: recoveryState,
            acceptanceState: acceptanceState,
            pendingReplacementState: pendingReplacementState,
            outboxWorkerState: outboxWorkerState,
            policyCutoverState: policyCutoverState,
            ownerIdentity: ownerIdentity,
            repositoryIdentityState: repositoryIdentityState,
            repositoryRegistration: repositoryRegistration
        )
    }

    func relaunchedCoordinator() -> IOSAcceptedHistoryCoordinator {
        let capabilityOwnerIdentity =
            IOSAcceptedHistoryCapabilityOwnerIdentity()
        let deliveryStoreIdentity = IOSAcceptedOutputDeliveryStoreIdentity()
        let outboxStoreIdentity = IOSAcceptedHistoryOutboxStoreIdentity()
        return IOSAcceptedHistoryCoordinator(
            policyStore: IOSHistoryPolicyStore(
                journal: policy,
                capabilityOwnerIdentity: capabilityOwnerIdentity
            ),
            acceptedHistoryStore: IOSAcceptedHistoryStore(
                journal: accepted,
                now: { [clock] in clock.now },
                capabilityOwnerIdentity: capabilityOwnerIdentity
            ),
            failedHistoryStore: IOSFailedHistoryStore(
                journal: FoundationIOSFailedHistoryJournalRepository(
                    fileSystem: failedHistoryFileSystem
                ),
                capabilityOwnerIdentity: capabilityOwnerIdentity,
                now: { [clock] in clock.now }
            ),
            outboxStore: IOSAcceptedHistoryOutboxStore(
                journal: outbox,
                now: { [clock] in clock.now },
                deliveryStoreIdentity: deliveryStoreIdentity,
                storeIdentity: outboxStoreIdentity,
                capabilityOwnerIdentity: capabilityOwnerIdentity
            ),
            deliveryStore: IOSAcceptedOutputDeliveryStore(
                journal: delivery,
                now: { [clock] in clock.now },
                monotonicNowNanoseconds: { [clock] in
                    clock.uptimeNanoseconds
                },
                storeIdentity: deliveryStoreIdentity,
                outboxStoreIdentity: outboxStoreIdentity,
                capabilityOwnerIdentity: capabilityOwnerIdentity
            ),
            operationGate: gate,
            acceptanceState: IOSAcceptedHistoryAcceptanceOperationState(),
            pendingReplacementState:
                IOSAcceptedHistoryPendingReplacementOperationState(),
            outboxWorkerState:
                IOSAcceptedHistoryOutboxWorkerOperationState(),
            policyCutoverState:
                IOSHistoryPolicyCutoverOperationState(),
            ownerIdentity: capabilityOwnerIdentity,
            repositoryIdentityState: repositoryIdentityState,
            repositoryRegistration: repositoryRegistration
        )
    }
}

private final class CoordinatorClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow = Date(timeIntervalSince1970: 1_900_000_000)
    private var storedUptimeNanoseconds: UInt64 = 1_000_000_000
    private var readCount = 0
    private var scheduledAdvances: [Int: TimeInterval] = [:]

    var now: Date {
        lock.withLock {
            readCount += 1
            if let seconds = scheduledAdvances.removeValue(forKey: readCount) {
                storedNow = storedNow.addingTimeInterval(seconds)
                storedUptimeNanoseconds += UInt64(seconds * 1_000_000_000)
            }
            return storedNow
        }
    }
    var uptimeNanoseconds: UInt64 {
        lock.withLock { storedUptimeNanoseconds }
    }

    func advance(seconds: TimeInterval) {
        lock.withLock {
            storedNow = storedNow.addingTimeInterval(seconds)
            storedUptimeNanoseconds += UInt64(seconds * 1_000_000_000)
        }
    }

    func rollBack(seconds: TimeInterval) {
        lock.withLock {
            storedNow = storedNow.addingTimeInterval(-seconds)
            storedUptimeNanoseconds += 1
        }
    }

    func advanceOnRead(
        _ additionalRead: Int,
        seconds: TimeInterval
    ) {
        lock.withLock {
            scheduledAdvances[readCount + additionalRead] = seconds
        }
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
    private var replaceFailures: [Int: Failure] = [:]
    private var nextReplaceRaceState: IOSHistoryPolicyState?
    private var replaceRaces: [Int: IOSHistoryPolicyState] = [:]
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

    func raceReplace(onCall call: Int, with state: IOSHistoryPolicyState) {
        lock.withLock { replaceRaces[call] = state }
    }

    func failReplace(
        onCall call: Int,
        with error: IOSHistoryPolicyError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            replaceFailures[call] = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
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
            if let raceState = replaceRaces.removeValue(
                forKey: storedReplaceCount
            ) ?? nextReplaceRaceState {
                snapshot = makeSnapshotLocked(raceState)
                nextReplaceRaceState = nil
            }
            guard snapshot == expected else {
                throw IOSHistoryPolicyError.compareAndSwapFailed
            }
            let replacement = makeSnapshotLocked(state)
            if let failure = replaceFailures.removeValue(
                forKey: storedReplaceCount
            ) {
                if failure.commitBeforeThrowing {
                    snapshot = replacement
                }
                throw failure.error
            }
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
    private struct Failure {
        let error: IOSAcceptedHistoryError
        let commitBeforeThrowing: Bool
    }

    private let lock = NSLock()
    private let events: CoordinatorEventRecorder
    private var snapshot: IOSAcceptedHistoryJournalSnapshot?
    private var nextRevisionToken: UInt64 = 1
    private var loadFailure: IOSAcceptedHistoryError?
    private var storedLoadCount = 0
    private var storedCreateCount = 0
    private var storedReplaceCount = 0
    private var createFailure: Failure?
    private var replaceFailures: [Int: Failure] = [:]
    var replaceBlocker: CoordinatorBoundaryBlocker?

    init(events: CoordinatorEventRecorder) { self.events = events }

    var loadCount: Int { lock.withLock { storedLoadCount } }
    var createCount: Int { lock.withLock { storedCreateCount } }
    var replaceCount: Int { lock.withLock { storedReplaceCount } }
    var currentEnvelope: IOSAcceptedHistoryEnvelope? {
        lock.withLock { snapshot?.envelope }
    }

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

    func failNextCreate(
        with error: IOSAcceptedHistoryError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            createFailure = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func failReplace(
        onCall call: Int,
        with error: IOSAcceptedHistoryError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            replaceFailures[call] = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
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
        _ = authorization
        return try lock.withLock {
            storedCreateCount += 1
            events.append("accepted.create")
            guard snapshot == nil else {
                throw IOSAcceptedHistoryError.slotOccupied
            }
            let created = makeSnapshotLocked(envelope)
            if let failure = createFailure {
                createFailure = nil
                if failure.commitBeforeThrowing { snapshot = created }
                throw failure.error
            }
            snapshot = created
            return created
        }
    }

    func replace(
        _ envelope: IOSAcceptedHistoryEnvelope,
        expected: IOSAcceptedHistoryJournalSnapshot,
        authorization: IOSAcceptedHistoryJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryJournalSnapshot {
        _ = authorization
        let replacement = try lock.withLock {
            storedReplaceCount += 1
            events.append("accepted.replace")
            guard snapshot == expected else {
                throw IOSAcceptedHistoryError.compareAndSwapFailed
            }
            let replacement = makeSnapshotLocked(envelope)
            if let failure = replaceFailures.removeValue(
                forKey: storedReplaceCount
            ) {
                if failure.commitBeforeThrowing { snapshot = replacement }
                throw failure.error
            }
            snapshot = replacement
            return replacement
        }
        replaceBlocker?.blockOnce()
        return replacement
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

    private func makeSnapshotLocked(
        _ envelope: IOSAcceptedHistoryEnvelope
    ) -> IOSAcceptedHistoryJournalSnapshot {
        IOSAcceptedHistoryJournalSnapshot(
            envelope: envelope,
            fileRevision: revisionLocked()
        )
    }
}

private final class CoordinatorOutboxJournal:
    IOSAcceptedHistoryOutboxJournalStoring,
    @unchecked Sendable {
    private struct Failure {
        let error: IOSAcceptedHistoryOutboxError
        let commitBeforeThrowing: Bool
    }

    private let lock = NSLock()
    private let events: CoordinatorEventRecorder
    private var snapshot: IOSAcceptedHistoryOutboxJournalSnapshot?
    private var nextRevisionToken: UInt64 = 1
    private var storedLoadCount = 0
    private var storedCreateCount = 0
    private var storedReplaceCount = 0
    private var loadFailure: IOSAcceptedHistoryOutboxError?
    private var createFailure: Failure?
    private var replaceFailures: [Int: Failure] = [:]

    init(events: CoordinatorEventRecorder) { self.events = events }
    var loadCount: Int { lock.withLock { storedLoadCount } }
    var createCount: Int { lock.withLock { storedCreateCount } }
    var replaceCount: Int { lock.withLock { storedReplaceCount } }
    var currentEnvelope: IOSAcceptedHistoryOutboxEnvelope? {
        lock.withLock { snapshot?.envelope }
    }

    func install(_ envelope: IOSAcceptedHistoryOutboxEnvelope) {
        lock.withLock {
            snapshot = IOSAcceptedHistoryOutboxJournalSnapshot(
                envelope: envelope,
                fileRevision: revisionLocked()
            )
        }
    }

    func failNextLoad(with error: IOSAcceptedHistoryOutboxError) {
        lock.withLock { loadFailure = error }
    }

    func failNextCreate(
        with error: IOSAcceptedHistoryOutboxError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            createFailure = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func failReplace(
        onCall call: Int,
        with error: IOSAcceptedHistoryOutboxError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            replaceFailures[call] = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func load() throws -> IOSAcceptedHistoryOutboxJournalSnapshot? {
        try lock.withLock {
            storedLoadCount += 1
            events.append("outbox.load")
            if let loadFailure {
                self.loadFailure = nil
                throw loadFailure
            }
            return snapshot
        }
    }

    func create(
        _ envelope: IOSAcceptedHistoryOutboxEnvelope,
        authorization: IOSAcceptedHistoryOutboxJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryOutboxJournalSnapshot {
        _ = authorization
        return try lock.withLock {
            storedCreateCount += 1
            events.append("outbox.create")
            guard snapshot == nil else {
                throw IOSAcceptedHistoryOutboxError.slotOccupied
            }
            let created = makeSnapshotLocked(envelope)
            if let failure = createFailure {
                createFailure = nil
                if failure.commitBeforeThrowing { snapshot = created }
                throw failure.error
            }
            snapshot = created
            return created
        }
    }

    func replace(
        _ envelope: IOSAcceptedHistoryOutboxEnvelope,
        expected: IOSAcceptedHistoryOutboxJournalSnapshot,
        authorization: IOSAcceptedHistoryOutboxJournalMutationAuthorization
    ) throws -> IOSAcceptedHistoryOutboxJournalSnapshot {
        _ = authorization
        return try lock.withLock {
            storedReplaceCount += 1
            events.append("outbox.replace")
            guard snapshot == expected else {
                throw IOSAcceptedHistoryOutboxError.compareAndSwapFailed
            }
            let replacement = makeSnapshotLocked(envelope)
            if let failure = replaceFailures.removeValue(
                forKey: storedReplaceCount
            ) {
                if failure.commitBeforeThrowing { snapshot = replacement }
                throw failure.error
            }
            snapshot = replacement
            return replacement
        }
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

    private func makeSnapshotLocked(
        _ envelope: IOSAcceptedHistoryOutboxEnvelope
    ) -> IOSAcceptedHistoryOutboxJournalSnapshot {
        IOSAcceptedHistoryOutboxJournalSnapshot(
            envelope: envelope,
            fileRevision: revisionLocked()
        )
    }
}

private final class CoordinatorDeliveryJournal:
    IOSAcceptedOutputDeliveryJournalStoring,
    @unchecked Sendable {
    private struct Failure {
        let error: IOSAcceptedOutputDeliveryError
        let commitBeforeThrowing: Bool
    }

    private let lock = NSLock()
    private let events: CoordinatorEventRecorder
    private var snapshot: IOSAcceptedOutputDeliveryJournalSnapshot?
    private var nextRevisionToken: UInt64 = 1
    private var storedLoadCount = 0
    private var storedCreateCount = 0
    private var storedReplaceCount = 0
    private var storedRemoveCount = 0
    private var createFailure: Failure?
    private var replaceFailures: [Int: Failure] = [:]
    private var removeFailure: Failure?
    private var loadFailures: [Int: IOSAcceptedOutputDeliveryError] = [:]
    private var loadBlockers: [Int: CoordinatorBoundaryBlocker] = [:]

    init(events: CoordinatorEventRecorder) { self.events = events }
    var loadCount: Int { lock.withLock { storedLoadCount } }
    var createCount: Int { lock.withLock { storedCreateCount } }
    var replaceCount: Int { lock.withLock { storedReplaceCount } }
    var removeCount: Int { lock.withLock { storedRemoveCount } }
    var currentRecord: IOSAcceptedOutputDeliveryRecord? {
        lock.withLock { snapshot?.record }
    }

    func install(_ record: IOSAcceptedOutputDeliveryRecord) {
        lock.withLock {
            snapshot = IOSAcceptedOutputDeliveryJournalSnapshot(
                record: record,
                fileRevision: revisionLocked()
            )
        }
    }

    func failNextCreate(
        with error: IOSAcceptedOutputDeliveryError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            createFailure = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func failLoad(
        onCall call: Int,
        with error: IOSAcceptedOutputDeliveryError
    ) {
        lock.withLock { loadFailures[call] = error }
    }

    func blockLoad(
        onCall call: Int,
        with blocker: CoordinatorBoundaryBlocker
    ) {
        lock.withLock { loadBlockers[call] = blocker }
    }

    func failReplace(
        onCall call: Int,
        with error: IOSAcceptedOutputDeliveryError,
        commitBeforeThrowing: Bool
    ) {
        lock.withLock {
            replaceFailures[call] = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func failNextRemove(
        with error: IOSAcceptedOutputDeliveryError,
        commitBeforeThrowing: Bool = false
    ) {
        lock.withLock {
            removeFailure = Failure(
                error: error,
                commitBeforeThrowing: commitBeforeThrowing
            )
        }
    }

    func load() throws -> IOSAcceptedOutputDeliveryJournalSnapshot? {
        let outcome = lock.withLock {
            storedLoadCount += 1
            events.append("delivery.load")
            let call = storedLoadCount
            let blocker = loadBlockers.removeValue(forKey: call)
            let result: Result<
                IOSAcceptedOutputDeliveryJournalSnapshot?,
                IOSAcceptedOutputDeliveryError
            > = if let failure = loadFailures.removeValue(forKey: call) {
                .failure(failure)
            } else {
                .success(snapshot)
            }
            return (result, blocker)
        }
        outcome.1?.blockOnce()
        return try outcome.0.get()
    }

    func loadOpaque() throws -> IOSAcceptedOutputDeliveryOpaqueSnapshot? { nil }

    func create(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        try lock.withLock {
            storedCreateCount += 1
            events.append("delivery.create")
            guard snapshot == nil else {
                throw IOSAcceptedOutputDeliveryError.slotOccupied
            }
            let created = makeSnapshotLocked(record)
            if let failure = createFailure {
                createFailure = nil
                if failure.commitBeforeThrowing { snapshot = created }
                throw failure.error
            }
            snapshot = created
            return created
        }
    }

    func replace(
        _ record: IOSAcceptedOutputDeliveryRecord,
        expected: IOSAcceptedOutputDeliveryJournalSnapshot
    ) throws -> IOSAcceptedOutputDeliveryJournalSnapshot {
        try lock.withLock {
            storedReplaceCount += 1
            events.append("delivery.replace")
            guard snapshot == expected else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            let replacement = makeSnapshotLocked(record)
            if let failure = replaceFailures.removeValue(
                forKey: storedReplaceCount
            ) {
                if failure.commitBeforeThrowing { snapshot = replacement }
                throw failure.error
            }
            snapshot = replacement
            return replacement
        }
    }

    func remove(expected: IOSAcceptedOutputDeliveryJournalSnapshot) throws {
        try lock.withLock {
            storedRemoveCount += 1
            events.append("delivery.remove")
            guard snapshot == expected else {
                throw IOSAcceptedOutputDeliveryError.compareAndSwapFailed
            }
            if let removeFailure {
                self.removeFailure = nil
                if removeFailure.commitBeforeThrowing {
                    snapshot = nil
                }
                throw removeFailure.error
            }
            snapshot = nil
        }
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

    private func makeSnapshotLocked(
        _ record: IOSAcceptedOutputDeliveryRecord
    ) -> IOSAcceptedOutputDeliveryJournalSnapshot {
        IOSAcceptedOutputDeliveryJournalSnapshot(
            record: record,
            fileRevision: revisionLocked()
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

private actor CoordinatorAsyncOperationBlocker {
    private var blockingContinuation: CheckedContinuation<Void, Never>?
    private var observerContinuations: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private var isSuspended = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            blockingContinuation = continuation
            isSuspended = true
            let observers = observerContinuations
            observerContinuations.removeAll()
            for observer in observers {
                observer.resume()
            }
        }
    }

    func waitUntilSuspended() async {
        guard !isSuspended else { return }
        await withCheckedContinuation { continuation in
            observerContinuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        blockingContinuation?.resume()
        blockingContinuation = nil
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

private func coordinatorHistoryEntry(
    index: Int,
    createdAt: Date,
    generation: Int64 = 1,
    acceptedText: String = "accepted"
) throws -> IOSAcceptedHistoryEntry {
    try IOSAcceptedHistoryEntry(
        deliveryID: coordinatorUUID(prefix: 0, index: index),
        transcriptID: coordinatorUUID(prefix: 3, index: index),
        acceptedText: acceptedText,
        outputIntent: .standard,
        createdAt: createdAt,
        policyGeneration: generation,
        transcriptionModel: "model",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250,
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

private func coordinatorOutboxEntry(
    index: Int,
    createdAt: Date,
    generation: Int64 = 1,
    acceptedText: String = "accepted"
) throws -> IOSAcceptedHistoryOutboxEntry {
    try IOSAcceptedHistoryOutboxEntry(
        deliveryID: coordinatorUUID(prefix: 0, index: index),
        transcriptID: coordinatorUUID(prefix: 3, index: index),
        acceptedText: acceptedText,
        outputIntent: .standard,
        createdAt: createdAt,
        expiresAt: createdAt.addingTimeInterval(86_400),
        policyGeneration: generation,
        transcriptionModel: "model",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250
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

private func coordinatorDeliveryRecord(
    matching entry: IOSAcceptedHistoryOutboxEntry,
    state: IOSAcceptedOutputHistoryWriteState,
    acceptedText: String? = nil
) throws -> IOSAcceptedOutputDeliveryRecord {
    let marker = try IOSAcceptedOutputHistoryWrite(
        state: state,
        policyGeneration: entry.policyGeneration,
        transcriptionModel: entry.transcriptionModel,
        transcriptionLanguageCode: entry.transcriptionLanguageCode,
        durationMilliseconds: entry.durationMilliseconds
    )
    return try IOSAcceptedOutputDeliveryRecord(
        revision: 1,
        deliveryID: entry.deliveryID,
        sessionID: coordinatorUUID(prefix: 1, index: 10_000),
        attemptID: coordinatorUUID(prefix: 2, index: 10_000),
        transcriptID: entry.transcriptID,
        acceptedText: acceptedText ?? entry.acceptedText,
        outputIntent: entry.outputIntent,
        createdAt: entry.createdAt,
        updatedAt: entry.createdAt,
        expiresAt: entry.expiresAt,
        deliveryState: .pending,
        automaticInsertionPreferenceEnabled: true,
        keepLatestResult: true,
        publicationGeneration: 0,
        historyWrite: marker
    )
}

private func coordinatorDiscardedDeliveryRecord(
    matching entry: IOSAcceptedHistoryOutboxEntry
) throws -> IOSAcceptedOutputDeliveryRecord {
    let active = try coordinatorDeliveryRecord(
        matching: entry,
        state: .pending
    )
    return try IOSAcceptedOutputDeliveryRecord(
        revision: active.revision + 1,
        deliveryID: active.deliveryID,
        sessionID: active.sessionID,
        attemptID: active.attemptID,
        transcriptID: active.transcriptID,
        acceptedText: nil,
        outputIntent: active.outputIntent,
        createdAt: active.createdAt,
        updatedAt: active.updatedAt,
        expiresAt: active.expiresAt,
        deliveryState: .discarded,
        automaticInsertionPreferenceEnabled: false,
        keepLatestResult: active.keepLatestResult,
        publicationGeneration: active.publicationGeneration,
        historyWrite: nil
    )
}

private func coordinatorUUID(prefix: Int, index: Int) -> UUID {
    UUID(
        uuidString: String(
            format: "%08x-0000-4000-8000-%012x",
            prefix,
            index
        )
    )!
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
