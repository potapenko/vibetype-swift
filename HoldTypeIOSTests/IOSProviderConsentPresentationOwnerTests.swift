import Foundation
@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSProviderConsentPresentationOwnerTests {
    @Test func constructionIsPassiveAndPrivacyLoadReadsOnlyPublicStatus()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        let probe = ConsentPresentationProbe(microphoneStatus: .denied)
        let owner = fixture.makeOwner(probe: probe)

        #expect(owner.privacyState == .notLoaded)
        #expect(owner.microphoneStatus == .unavailable)
        #expect(probe.observeCount == 0)
        #expect(probe.microphoneReadCount == 0)

        await owner.activatePrivacy()

        #expect(
            owner.privacyState == .ready(
                IOSProviderConsentPrivacySnapshot(
                    status: .notReviewed,
                    decisionAt: nil,
                    canResetUnreadableData: false,
                    requiresExplicitAcceptance: false
                )
            )
        )
        #expect(owner.microphoneStatus == .denied)
        #expect(probe.observeCount == 1)
        #expect(probe.microphoneReadCount == 1)
        #expect(probe.acceptCount == 0)
        #expect(probe.withdrawCount == 0)
        #expect(probe.resetCount == 0)
    }

    @Test func exactInitiatingSceneAcceptsAndResumesSameStart()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        let owner = fixture.makeOwner()
        let first = fixture.registry.registerScene(initialActivity: .active)
        let second = fixture.registry.registerScene(initialActivity: .active)
        let lease = try #require(first.acquireStartLease())
        let observation = await owner.observeForVoicePreflight()

        let continuation = Task { @MainActor in
            await owner.continueVoiceStart(
                lease: lease,
                observation: observation
            )
        }
        try await consentEventually { owner.voicePrompt != nil }
        let prompt = try #require(owner.voicePrompt)

        #expect(first.promptPresentation == .ownedByThisScene)
        #expect(second.promptPresentation == .ownedByAnotherScene)
        let capability = try #require(first.promptDecisionCapability())
        #expect(second.promptDecisionCapability() == nil)
        owner.acceptVoicePrompt(prompt.id, from: capability)
        await owner.waitUntilIdle()
        let accepted = try #require(await continuation.value)

        #expect(accepted.status == .acceptedCurrentDisclosure)
        #expect(fixture.coordinator.makeAuthorization(from: accepted) != nil)
        #expect(owner.notice == .accepted)
        #expect(owner.failure == nil)
        #expect(owner.voicePrompt == nil)
        #expect(lease.finish())
    }

    @Test func dismissalAndTaskCancellationNeverMutateConsent()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        let probe = ConsentPresentationProbe()
        let owner = fixture.makeOwner(probe: probe)
        let scene = fixture.registry.registerScene(initialActivity: .active)

        let firstLease = try #require(scene.acquireStartLease())
        let firstObservation = await owner.observeForVoicePreflight()
        let dismissed = Task { @MainActor in
            await owner.continueVoiceStart(
                lease: firstLease,
                observation: firstObservation
            )
        }
        try await consentEventually { owner.voicePrompt != nil }
        let firstPrompt = try #require(owner.voicePrompt)
        let firstCapability = try #require(
            scene.promptDecisionCapability()
        )
        owner.dismissVoicePrompt(
            firstPrompt.id,
            from: firstCapability
        )
        #expect(await dismissed.value == nil)
        #expect(firstLease.finish())

        let secondLease = try #require(scene.acquireStartLease())
        let secondObservation = await owner.observeForVoicePreflight()
        let cancelled = Task { @MainActor in
            await owner.continueVoiceStart(
                lease: secondLease,
                observation: secondObservation
            )
        }
        try await consentEventually { owner.voicePrompt != nil }
        cancelled.cancel()
        #expect(await cancelled.value == nil)
        #expect(owner.voicePrompt == nil)
        #expect(probe.acceptCount == 0)
        #expect(probe.withdrawCount == 0)
        #expect(secondLease.finish())
    }

    @Test func initiatingSceneLossDismissesWithoutPromptTransfer()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        let owner = fixture.makeOwner()
        let first = fixture.registry.registerScene(initialActivity: .active)
        let second = fixture.registry.registerScene(initialActivity: .active)
        let lease = try #require(first.acquireStartLease())
        let observation = await owner.observeForVoicePreflight()
        let continuation = Task { @MainActor in
            await owner.continueVoiceStart(
                lease: lease,
                observation: observation
            )
        }
        try await consentEventually { owner.voicePrompt != nil }

        #expect(first.updateActivity(.inactive) == .accepted)
        #expect(await continuation.value == nil)
        #expect(owner.voicePrompt == nil)
        #expect(second.promptPresentation == .available)
        #expect(!lease.finish())
    }

    @Test func lateAcceptanceAfterSceneLossCannotResumeStart()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        let gate = ConsentPresentationGate()
        let owner = fixture.makeOwner(acceptGate: gate)
        let scene = fixture.registry.registerScene(initialActivity: .active)
        let lease = try #require(scene.acquireStartLease())
        let observation = await owner.observeForVoicePreflight()
        let continuation = Task { @MainActor in
            await owner.continueVoiceStart(
                lease: lease,
                observation: observation
            )
        }
        try await consentEventually { owner.voicePrompt != nil }
        let prompt = try #require(owner.voicePrompt)
        let capability = try #require(scene.promptDecisionCapability())
        owner.acceptVoicePrompt(prompt.id, from: capability)
        try await consentEventually { owner.operation == .acceptingVoice }

        #expect(scene.updateActivity(.inactive) == .accepted)
        #expect(await continuation.value == nil)
        await gate.open()
        await owner.waitUntilIdle()

        let current = await fixture.coordinator.observe()
        #expect(current.status == .acceptedCurrentDisclosure)
        #expect(owner.voicePrompt == nil)
        #expect(!lease.finish())
    }

    @Test func declinePersistsWithdrawalAndSignalsVoiceInvalidation()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        let invalidations = ConsentPresentationProbe()
        let owner = fixture.makeOwner()
        owner.bindVoiceInvalidation { invalidations.recordInvalidation() }
        let scene = fixture.registry.registerScene(initialActivity: .active)
        let lease = try #require(scene.acquireStartLease())
        let observation = await owner.observeForVoicePreflight()
        let continuation = Task { @MainActor in
            await owner.continueVoiceStart(
                lease: lease,
                observation: observation
            )
        }
        try await consentEventually { owner.voicePrompt != nil }
        let prompt = try #require(owner.voicePrompt)

        let capability = try #require(scene.promptDecisionCapability())
        owner.declineVoicePrompt(prompt.id, from: capability)
        await owner.waitUntilIdle()
        #expect(await continuation.value == nil)
        try await consentEventually { invalidations.invalidationCount == 1 }

        let current = await fixture.coordinator.observe()
        #expect(current.status == .withdrawn)
        #expect(owner.notice == .withdrawn)
        #expect(lease.finish())
    }

    @Test func anotherSceneCannotAcceptDeclineOrDismissSharedPrompt()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        let probe = ConsentPresentationProbe()
        let owner = fixture.makeOwner(probe: probe)
        let first = fixture.registry.registerScene(initialActivity: .active)
        let second = fixture.registry.registerScene(initialActivity: .active)

        let priorLease = try #require(second.acquireStartLease())
        let staleForeignCapability = try #require(
            second.promptDecisionCapability()
        )
        #expect(priorLease.finish())

        let lease = try #require(first.acquireStartLease())
        let observation = await owner.observeForVoicePreflight()
        let continuation = Task { @MainActor in
            await owner.continueVoiceStart(
                lease: lease,
                observation: observation
            )
        }
        try await consentEventually { owner.voicePrompt != nil }
        let prompt = try #require(owner.voicePrompt)

        owner.acceptVoicePrompt(
            prompt.id,
            from: staleForeignCapability
        )
        owner.declineVoicePrompt(
            prompt.id,
            from: staleForeignCapability
        )
        owner.dismissVoicePrompt(
            prompt.id,
            from: staleForeignCapability
        )

        #expect(owner.voicePrompt == prompt)
        #expect(probe.acceptCount == 0)
        #expect(probe.withdrawCount == 0)
        let owningCapability = try #require(
            first.promptDecisionCapability()
        )
        owner.dismissVoicePrompt(prompt.id, from: owningCapability)
        #expect(await continuation.value == nil)
        #expect(lease.finish())
    }

    @Test func privacyWithdrawalUsesExactConfirmationAndIsFailClosed()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.accept(
            using: fixture.coordinator.observe(),
            decisionAt: fixture.now
        )
        let invalidations = ConsentPresentationProbe()
        let owner = fixture.makeOwner()
        owner.bindVoiceInvalidation { invalidations.recordInvalidation() }
        await owner.activatePrivacy()
        let token = try #require(
            owner.makePrivacyConfirmation(for: .withdraw)
        )

        owner.confirmPrivacyAction(token)
        owner.confirmPrivacyAction(token)
        await owner.waitUntilIdle()
        try await consentEventually { invalidations.invalidationCount == 1 }

        let snapshot = try #require(privacySnapshot(owner.privacyState))
        #expect(snapshot.status == .withdrawn)
        #expect(owner.notice == .withdrawn)
        #expect(owner.failure == nil)
        #expect(
            owner.makePrivacyConfirmation(for: .withdraw) == nil
        )
    }

    @Test func privacyConfirmationValidityTracksExactProcessToken()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.accept(
            using: fixture.coordinator.observe(),
            decisionAt: fixture.now
        )
        let owner = fixture.makeOwner()
        await owner.activatePrivacy()

        let stale = try #require(
            owner.makePrivacyConfirmation(for: .withdraw)
        )
        #expect(owner.isPrivacyConfirmationCurrent(stale))
        let current = try #require(
            owner.makePrivacyConfirmation(for: .withdraw)
        )
        #expect(!owner.isPrivacyConfirmationCurrent(stale))
        #expect(owner.isPrivacyConfirmationCurrent(current))
        #expect(owner.confirmPrivacyAction(stale) == .stale)

        await owner.activatePrivacy()
        #expect(!owner.isPrivacyConfirmationCurrent(current))
        #expect(owner.confirmPrivacyAction(current) == .stale)
        let refreshed = try #require(
            owner.makePrivacyConfirmation(for: .withdraw)
        )
        #expect(owner.confirmPrivacyAction(refreshed) == .accepted)
        #expect(!owner.isPrivacyConfirmationCurrent(refreshed))
        await owner.waitUntilIdle()
    }

    @Test func preflightObservationCannotOverwriteQueuedWithdrawal()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.accept(
            using: fixture.coordinator.observe(),
            decisionAt: fixture.now
        )
        let observeGate = ConsentPresentationGate()
        let probe = ConsentPresentationProbe()
        let owner = fixture.makeOwner(
            probe: probe,
            observeGateAfterFirstLoad: observeGate
        )
        await owner.activatePrivacy()
        let scene = fixture.registry.registerScene(initialActivity: .active)
        let lease = try #require(scene.acquireStartLease())
        let start = Task { @MainActor in
            let observation = await owner.observeForVoicePreflight()
            return await owner.continueVoiceStart(
                lease: lease,
                observation: observation
            )
        }
        try await consentEventually { probe.observeCount == 2 }
        let token = try #require(
            owner.makePrivacyConfirmation(for: .withdraw)
        )

        owner.confirmPrivacyAction(token)
        await observeGate.open()
        #expect(await start.value == nil)
        await owner.waitUntilIdle()

        let snapshot = try #require(privacySnapshot(owner.privacyState))
        #expect(snapshot.status == .withdrawn)
        #expect(owner.voicePrompt == nil)
        #expect(lease.finish())
    }

    @Test func olderObserveCannotPublishAfterNewerWithdrawal()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.accept(
            using: fixture.coordinator.observe(),
            decisionAt: fixture.now
        )
        let interposition = ConsentPublicationInterposition(
            heldSequence: 2
        )
        let owner = fixture.makeOwner(beforePublication: { sequence in
            await interposition.pauseIfNeeded(sequence)
        })
        await owner.activatePrivacy()
        let token = try #require(
            owner.makePrivacyConfirmation(for: .withdraw)
        )
        let scene = fixture.registry.registerScene(initialActivity: .active)
        let lease = try #require(scene.acquireStartLease())
        let start = Task { @MainActor in
            let observation = await owner.observeForVoicePreflight()
            return await owner.continueVoiceStart(
                lease: lease,
                observation: observation
            )
        }
        await interposition.waitUntilPaused()

        owner.confirmPrivacyAction(token)
        await owner.waitUntilIdle()
        let withdrawn = try #require(privacySnapshot(owner.privacyState))
        #expect(withdrawn.status == .withdrawn)
        await interposition.release()
        #expect(await start.value == nil)

        let final = try #require(privacySnapshot(owner.privacyState))
        #expect(final.status == .withdrawn)
        #expect(owner.voicePrompt == nil)
        #expect(lease.finish())
    }

    @Test func olderNotReviewedObserveCannotPublishAfterNewerAcceptance()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        let interposition = ConsentPublicationInterposition(
            heldSequence: 2
        )
        let owner = fixture.makeOwner(beforePublication: { sequence in
            await interposition.pauseIfNeeded(sequence)
        })
        await owner.activatePrivacy()
        let token = try #require(
            owner.makePrivacyConfirmation(for: .acceptCurrentDisclosure)
        )
        let scene = fixture.registry.registerScene(initialActivity: .active)
        let lease = try #require(scene.acquireStartLease())
        let start = Task { @MainActor in
            let observation = await owner.observeForVoicePreflight()
            return await owner.continueVoiceStart(
                lease: lease,
                observation: observation
            )
        }
        await interposition.waitUntilPaused()

        owner.confirmPrivacyAction(token)
        await owner.waitUntilIdle()
        let accepted = try #require(privacySnapshot(owner.privacyState))
        #expect(accepted.status == .acceptedCurrentDisclosure)
        #expect(!accepted.requiresExplicitAcceptance)
        await interposition.release()
        #expect(await start.value == nil)

        let final = try #require(privacySnapshot(owner.privacyState))
        #expect(final.status == .acceptedCurrentDisclosure)
        #expect(!final.requiresExplicitAcceptance)
        #expect(owner.voicePrompt == nil)
        #expect(lease.finish())
    }

    @Test func privacyCanExplicitlyReacceptDurableAcceptanceAfterGateClose()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.accept(
            using: fixture.coordinator.observe(),
            decisionAt: fixture.now
        )
        fixture.coordinator.invalidateProviderAuthorizations()
        let owner = fixture.makeOwner()
        await owner.activatePrivacy()

        let closed = try #require(privacySnapshot(owner.privacyState))
        #expect(closed.status == .acceptedCurrentDisclosure)
        #expect(closed.requiresExplicitAcceptance)
        let token = try #require(
            owner.makePrivacyConfirmation(for: .acceptCurrentDisclosure)
        )
        owner.confirmPrivacyAction(token)
        await owner.waitUntilIdle()

        let reopened = try #require(privacySnapshot(owner.privacyState))
        #expect(reopened.status == .acceptedCurrentDisclosure)
        #expect(!reopened.requiresExplicitAcceptance)
        let current = await fixture.coordinator.observe()
        #expect(fixture.coordinator.isAuthorizationReady(for: current))
        #expect(fixture.coordinator.makeAuthorization(from: current) != nil)
    }

    @Test func voiceCanExplicitlyReacceptDurableAcceptanceAfterGateClose()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.accept(
            using: fixture.coordinator.observe(),
            decisionAt: fixture.now
        )
        fixture.coordinator.invalidateProviderAuthorizations()
        let owner = fixture.makeOwner()
        let scene = fixture.registry.registerScene(initialActivity: .active)
        let lease = try #require(scene.acquireStartLease())
        let observation = await owner.observeForVoicePreflight()
        let continuation = Task { @MainActor in
            await owner.continueVoiceStart(
                lease: lease,
                observation: observation
            )
        }
        try await consentEventually { owner.voicePrompt != nil }
        let prompt = try #require(owner.voicePrompt)
        let capability = try #require(scene.promptDecisionCapability())

        owner.acceptVoicePrompt(prompt.id, from: capability)
        await owner.waitUntilIdle()
        let reopened = try #require(await continuation.value)

        #expect(fixture.coordinator.isAuthorizationReady(for: reopened))
        #expect(fixture.coordinator.makeAuthorization(from: reopened) != nil)
        #expect(lease.finish())
    }

    @Test func failedWithdrawalFenceRotationRejectsStaleStartAndReaccepts()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.accept(
            using: fixture.coordinator.observe(),
            decisionAt: fixture.now
        )
        let interposition = ConsentPublicationInterposition(
            heldSequence: 2
        )
        let failurePlan = ConsentPresentationFailurePlan(
            failNextWithdrawalAfterClose: true
        )
        let owner = fixture.makeOwner(
            failurePlan: failurePlan,
            beforePublication: { sequence in
                await interposition.pauseIfNeeded(sequence)
            }
        )
        await owner.activatePrivacy()
        let withdrawal = try #require(
            owner.makePrivacyConfirmation(for: .withdraw)
        )
        let scene = fixture.registry.registerScene(initialActivity: .active)
        let lease = try #require(scene.acquireStartLease())
        let staleStart = Task { @MainActor in
            let observation = await owner.observeForVoicePreflight()
            return await owner.continueVoiceStart(
                lease: lease,
                observation: observation
            )
        }
        await interposition.waitUntilPaused()

        owner.confirmPrivacyAction(withdrawal)
        await owner.waitUntilIdle()
        let refreshed = try #require(privacySnapshot(owner.privacyState))
        #expect(refreshed.status == .acceptedCurrentDisclosure)
        #expect(refreshed.requiresExplicitAcceptance)
        await interposition.release()
        #expect(await staleStart.value == nil)
        #expect(owner.voicePrompt == nil)

        let fresh = await owner.observeForVoicePreflight()
        let reaccept = Task { @MainActor in
            await owner.continueVoiceStart(
                lease: lease,
                observation: fresh
            )
        }
        try await consentEventually { owner.voicePrompt != nil }
        let prompt = try #require(owner.voicePrompt)
        let capability = try #require(scene.promptDecisionCapability())
        owner.acceptVoicePrompt(prompt.id, from: capability)
        await owner.waitUntilIdle()
        let reopened = try #require(await reaccept.value)

        #expect(fixture.coordinator.isAuthorizationReady(for: reopened))
        #expect(fixture.coordinator.makeAuthorization(from: reopened) != nil)
        #expect(lease.finish())
    }

    @Test func privacyResetRemovesOnlyExactUnreadableConsentRecord()
        async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        _ = try await fixture.coordinator.accept(
            using: fixture.coordinator.observe(),
            decisionAt: fixture.now
        )
        try fixture.writeUnreadableConsent()
        let probe = ConsentPresentationProbe()
        let owner = fixture.makeOwner(probe: probe)
        await owner.activatePrivacy()
        let unreadable = try #require(privacySnapshot(owner.privacyState))
        #expect(unreadable.canResetUnreadableData)
        let token = try #require(
            owner.makePrivacyConfirmation(for: .resetUnreadableData)
        )

        owner.confirmPrivacyAction(token)
        await owner.waitUntilIdle()

        let reset = try #require(privacySnapshot(owner.privacyState))
        #expect(reset.status == .notReviewed)
        #expect(!reset.canResetUnreadableData)
        #expect(owner.notice == .unreadableDataReset)
        #expect(probe.resetCount == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.consentURL.path))
    }

    @Test func allPublicPresentationValuesAreRedacted() async throws {
        let fixture = try ConsentPresentationFixture()
        defer { fixture.remove() }
        let owner = fixture.makeOwner()
        await owner.activatePrivacy()
        let snapshot = try #require(privacySnapshot(owner.privacyState))
        let token = try #require(
            owner.makePrivacyConfirmation(for: .acceptCurrentDisclosure)
        )
        let values: [Any] = [
            owner,
            owner.privacyState,
            snapshot,
            owner.operation,
            IOSProviderConsentPresentationNotice.accepted,
            IOSProviderConsentPresentationFailure.operationFailed,
            IOSProviderConsentPrivacyAction.acceptCurrentDisclosure,
            token,
        ]

        for value in values {
            let described = String(describing: value)
            let reflected = String(reflecting: value)
            #expect(described.localizedCaseInsensitiveContains("redacted"))
            #expect(reflected.localizedCaseInsensitiveContains("redacted"))
            #expect(Mirror(reflecting: value).children.isEmpty)
        }
    }
}

@MainActor
private final class ConsentPresentationFixture {
    let root: URL
    let coordinator: IOSProviderConsentCoordinator
    let registry = IOSVoiceSceneRegistry()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    var consentURL: URL {
        root.appendingPathComponent(
            "HoldType/ios-openai-provider-consent.json"
        )
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "consent-presentation-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        coordinator = IOSProviderConsentCoordinator(
            applicationSupportDirectoryURL: root
        )
    }

    func makeOwner(
        probe: ConsentPresentationProbe = ConsentPresentationProbe(),
        acceptGate: ConsentPresentationGate? = nil,
        observeGateAfterFirstLoad: ConsentPresentationGate? = nil,
        failurePlan: ConsentPresentationFailurePlan? = nil,
        beforePublication:
            @escaping IOSProviderConsentPresentationOwner.BeforePublication = {
                _ in
            }
    ) -> IOSProviderConsentPresentationOwner {
        let coordinator = coordinator
        let now = now
        return IOSProviderConsentPresentationOwner(
            client: IOSProviderConsentPresentationClient(
                observe: {
                    let count = probe.recordObserve()
                    if count > 1, let observeGateAfterFirstLoad {
                        await observeGateAfterFirstLoad.wait()
                    }
                    return await coordinator.observe()
                },
                accept: { observation, decisionAt in
                    probe.recordAccept()
                    if let acceptGate { await acceptGate.wait() }
                    return try await coordinator.accept(
                        using: observation,
                        decisionAt: decisionAt
                    )
                },
                withdraw: {
                    observation,
                    decisionAt,
                    authorizationDidClose in
                    probe.recordWithdraw()
                    if failurePlan?.consumeWithdrawalFailure() == true {
                        coordinator.invalidateProviderAuthorizations()
                        await authorizationDidClose()
                        throw IOSProviderConsentError.mutationNotSaved
                    }
                    return try await coordinator.withdraw(
                        using: observation,
                        decisionAt: decisionAt,
                        authorizationDidClose: authorizationDidClose
                    )
                },
                resetUnreadableData: {
                    observation,
                    authorizationDidClose in
                    probe.recordReset()
                    return try await coordinator.resetUnreadableConsentData(
                        using: observation,
                        authorizationDidClose: authorizationDidClose
                    )
                },
                isAuthorizationReady: { observation in
                    coordinator.isAuthorizationReady(for: observation)
                },
                hasSameObservationAuthority: { candidate, current in
                    coordinator.hasSameObservationAuthority(
                        candidate,
                        as: current
                    )
                }
            ),
            sceneRegistry: registry,
            readMicrophoneStatus: {
                probe.readMicrophoneStatus()
            },
            now: { now },
            beforePublication: beforePublication
        )
    }

    func writeUnreadableConsent() throws {
        try FileManager.default.createDirectory(
            at: consentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{".utf8).write(to: consentURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class ConsentPresentationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let storedMicrophoneStatus: IOSMicrophonePermissionStatus
    private var storedObserveCount = 0
    private var storedMicrophoneReadCount = 0
    private var storedAcceptCount = 0
    private var storedWithdrawCount = 0
    private var storedResetCount = 0
    private var storedInvalidationCount = 0

    init(
        microphoneStatus: IOSMicrophonePermissionStatus = .unavailable
    ) {
        storedMicrophoneStatus = microphoneStatus
    }

    var observeCount: Int { lock.withLock { storedObserveCount } }
    var microphoneReadCount: Int {
        lock.withLock { storedMicrophoneReadCount }
    }
    var acceptCount: Int { lock.withLock { storedAcceptCount } }
    var withdrawCount: Int { lock.withLock { storedWithdrawCount } }
    var resetCount: Int { lock.withLock { storedResetCount } }
    var invalidationCount: Int {
        lock.withLock { storedInvalidationCount }
    }

    func recordObserve() -> Int {
        lock.withLock {
            storedObserveCount += 1
            return storedObserveCount
        }
    }
    func recordAccept() { lock.withLock { storedAcceptCount += 1 } }
    func recordWithdraw() { lock.withLock { storedWithdrawCount += 1 } }
    func recordReset() { lock.withLock { storedResetCount += 1 } }
    func recordInvalidation() {
        lock.withLock { storedInvalidationCount += 1 }
    }

    func readMicrophoneStatus() -> IOSMicrophonePermissionStatus {
        lock.withLock {
            storedMicrophoneReadCount += 1
            return storedMicrophoneStatus
        }
    }
}

private final class ConsentPresentationFailurePlan: @unchecked Sendable {
    private let lock = NSLock()
    private var failNextWithdrawalAfterClose: Bool

    init(failNextWithdrawalAfterClose: Bool) {
        self.failNextWithdrawalAfterClose = failNextWithdrawalAfterClose
    }

    func consumeWithdrawalFailure() -> Bool {
        lock.withLock {
            defer { failNextWithdrawalAfterClose = false }
            return failNextWithdrawalAfterClose
        }
    }
}

private actor ConsentPresentationGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor ConsentPublicationInterposition {
    private let heldSequence: UInt64
    private var isPaused = false
    private var isReleased = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(heldSequence: UInt64) {
        self.heldSequence = heldSequence
    }

    func pauseIfNeeded(_ sequence: UInt64) async {
        guard sequence == heldSequence else { return }
        isPaused = true
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
        }
    }

    func waitUntilPaused() async {
        guard !isPaused else { return }
        await withCheckedContinuation { continuation in
            pauseWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
private func consentEventually(
    _ condition: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<300 {
        if condition() { return }
        await Task.yield()
    }
    throw ConsentPresentationTestError.timedOut
}

private func privacySnapshot(
    _ state: IOSProviderConsentPrivacyState
) -> IOSProviderConsentPrivacySnapshot? {
    guard case .ready(let snapshot) = state else { return nil }
    return snapshot
}

private enum ConsentPresentationTestError: Error {
    case timedOut
}
