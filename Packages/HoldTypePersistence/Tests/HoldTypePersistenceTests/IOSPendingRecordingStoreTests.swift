import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSPendingRecordingStoreTests {
    @Test func storeIdentityIsOpaqueAndGateBindingIsOneTime() {
        let gate = IOSPersistenceOperationGate()
        let store = IOSPendingRecordingStore(
            journal: FakePendingRecordingJournal(
                events: PendingStoreEventLog()
            ),
            audioFileSystem: FakePendingRecordingAudioFileSystem(
                events: PendingStoreEventLog()
            ),
            operationGate: gate
        )

        #expect(store.bindOperationGateIdentity(gate.identity))
        #expect(
            !store.bindOperationGateIdentity(
                IOSPersistenceOperationGate().identity
            )
        )
        #expect(
            String(describing: store.storeIdentity)
                == "IOSPendingRecordingStoreIdentity(redacted)"
        )
        #expect(store.storeIdentity.customMirror.children.isEmpty)
    }

    @Test func publicStoresShareCanonicalRootOwnerAndStoreIdentity() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pending-root-identity-\(UUID().uuidString)",
            isDirectory: true
        )
        let firstRoot = base.appendingPathComponent("first", isDirectory: true)
        let secondRoot = base.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(
            at: firstRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondRoot,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: base) }

        let first = IOSPendingRecordingStore(
            applicationSupportDirectoryURL: firstRoot
        )
        let sameRoot = IOSPendingRecordingStore(
            applicationSupportDirectoryURL: firstRoot
        )
        let differentRoot = IOSPendingRecordingStore(
            applicationSupportDirectoryURL: secondRoot
        )

        #expect(first.storeIdentity == sameRoot.storeIdentity)
        #expect(
            first.capabilityOwnerIdentity
                == sameRoot.capabilityOwnerIdentity
        )
        #expect(
            first.failedHistoryRetryState.identity
                == sameRoot.failedHistoryRetryState.identity
        )
        #expect(first.storeIdentity != differentRoot.storeIdentity)
        #expect(
            first.capabilityOwnerIdentity
                != differentRoot.capabilityOwnerIdentity
        )
        #expect(
            first.failedHistoryRetryState.identity
                != differentRoot.failedHistoryRetryState.identity
        )
    }

    @Test func publicStoreFailsClosedAfterPhysicalRootReplacement() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pending-root-replacement-\(UUID().uuidString)",
            isDirectory: true
        )
        let root = parent.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = IOSPendingRecordingStore(
            applicationSupportDirectoryURL: root
        )
        try await clearProductionRetryRecoveryBarrier(at: root)

        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )

        await #expect(
            throws: IOSPendingRecordingError.repositoryIdentityConflict
        ) {
            _ = try await store.load()
        }
    }

    @Test func publicSymlinkAliasUsesCanonicalRootWithoutPoisoningOwner()
        async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pending-root-alias-\(UUID().uuidString)",
            isDirectory: true
        )
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let alias = parent.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: alias,
            withDestinationURL: root
        )
        defer { try? FileManager.default.removeItem(at: parent) }

        try await clearProductionRetryRecoveryBarrier(at: root)
        let canonical = IOSPendingRecordingStore(
            applicationSupportDirectoryURL: root
        )
        let aliased = IOSPendingRecordingStore(
            applicationSupportDirectoryURL: alias
        )

        #expect(canonical.storeIdentity == aliased.storeIdentity)
        #expect(
            canonical.capabilityOwnerIdentity
                == aliased.capabilityOwnerIdentity
        )
        #expect(try await aliased.load() == nil)
        #expect(try await canonical.load() == nil)
    }

    @Test func failedHistoryUncertaintyBlocksPendingBeforeRepositoryIO()
        async throws {
        let events = PendingStoreEventLog()
        let interlock = IOSFailedHistoryMutationInterlock()
        let failedStore = IOSFailedHistoryStore(
            journal: FoundationIOSFailedHistoryJournalRepository(
                fileSystem: FailedHistoryFakeFileSystem()
            ),
            capabilityOwnerIdentity:
                IOSAcceptedHistoryCapabilityOwnerIdentity(),
            mutationInterlock: interlock
        )
        let store = IOSPendingRecordingStore(
            journal: FakePendingRecordingJournal(events: events),
            audioFileSystem: FakePendingRecordingAudioFileSystem(
                events: events
            ),
            failedHistoryMutationInterlock: interlock
        )
        await failedStore.retainMutationUncertaintyForTesting()

        await #expect(throws: IOSPendingRecordingError.localRecoveryPending) {
            _ = try await store.load()
        }
        #expect(events.values.isEmpty)
    }

    @Test func failedHistoryInterlockWinsBeforeProductionRootRevalidation()
        async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "pending-interlock-before-root-\(UUID().uuidString)",
            isDirectory: true
        )
        let root = parent.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let registry = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
        let context = registry.context(for: root)
        await context.failedHistoryStore.retainMutationUncertaintyForTesting()

        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )

        await #expect(throws: IOSPendingRecordingError.localRecoveryPending) {
            _ = try await context.pendingRecordingStore.load()
        }
        #expect(!context.repositoryIdentityState.isConflicted)
    }

    @Test func preparePublishesAndRevalidatesAudioAroundJournalCommit() async throws {
        let fixture = StoreFixture()

        let recording = try await fixture.store.prepare(fixture.preparation())

        #expect(recording.phase == .readyForTranscription)
        #expect(recording.transcriptionID == nil)
        #expect(fixture.journal.recording == recording)
        #expect(
            fixture.events.values == [
                "audio.namespace.empty",
                "audio.publish",
                "audio.lease.revalidate",
                "journal.create",
                "audio.lease.revalidate",
                "audio.lease.release",
            ]
        )
        #expect(fixture.audio.published)
    }

    @Test func productionPrepareUsesSealedFailedInventoryInsteadOfEmptyNamespace()
        async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "pending-inventory-prepare-\(UUID().uuidString)",
                isDirectory: true
            )
        let root = parent.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let context = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
            .context(for: root)
        let events = PendingStoreEventLog()
        let journal = FakePendingRecordingJournal(events: events)
        let audio = FakePendingRecordingAudioFileSystem(events: events)
        let store = IOSPendingRecordingStore(
            journal: journal,
            audioFileSystem: audio,
            operationGate: context.operationGate,
            liveOwnerRegistry: context.pendingRecordingLiveOwnerRegistry,
            capabilityOwnerIdentity: context.ownerIdentity,
            storeIdentity: context.pendingRecordingStoreIdentity,
            repositoryGuard: context.repositoryGuard,
            failedHistoryMutationInterlock:
                context.failedHistoryMutationInterlock,
            failedOwnershipInspector: context.failedHistoryStore,
            now: { Date(timeIntervalSince1970: 1_752_150_896.789) }
        )
        let preparation = try IOSPendingRecordingPreparation(
            attemptID: UUID(
                uuidString: "01234567-89AB-CDEF-8123-456789ABCDEF"
            )!,
            sourceArtifact: AudioRecordingArtifact(
                fileURL: URL(fileURLWithPath: "/runtime/source.m4a"),
                duration: 1.5,
                byteCount: 12
            ),
            initialState: .readyForTranscription,
            outputIntent: .translate,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "initial-model",
                language: .english,
                freeformPrompt: "not durable"
            )
        )

        let recording = try await store.prepare(preparation)

        #expect(journal.recording == recording)
        #expect(audio.published)
        #expect(
            events.values == [
                "audio.inventory.validate",
                "audio.inventory.publish",
                "audio.lease.revalidate",
                "journal.create",
                "audio.lease.revalidate",
                "audio.lease.release",
            ]
        )
        #expect(!events.values.contains("audio.namespace.empty"))
        #expect(!events.values.contains("audio.publish"))
    }

    @Test func productionEmptyLoadValidatesExactFailedInventory() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "pending-inventory-load-\(UUID().uuidString)",
                isDirectory: true
            )
        let root = parent.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let context = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
            .context(for: root)
        let events = PendingStoreEventLog()
        let store = IOSPendingRecordingStore(
            journal: FakePendingRecordingJournal(events: events),
            audioFileSystem: FakePendingRecordingAudioFileSystem(
                events: events
            ),
            operationGate: context.operationGate,
            liveOwnerRegistry: context.pendingRecordingLiveOwnerRegistry,
            capabilityOwnerIdentity: context.ownerIdentity,
            storeIdentity: context.pendingRecordingStoreIdentity,
            repositoryGuard: context.repositoryGuard,
            failedHistoryMutationInterlock:
                context.failedHistoryMutationInterlock,
            failedOwnershipInspector: context.failedHistoryStore,
            now: { Date(timeIntervalSince1970: 1_752_150_896.789) }
        )

        #expect(try await store.load() == nil)
        #expect(events.values == ["audio.inventory.validate"])
        #expect(!events.values.contains("audio.namespace.empty"))
    }

    @Test func postPublishInventoryFailureReleasesCreatorLease() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "pending-inventory-release-\(UUID().uuidString)",
                isDirectory: true
            )
        let root = parent.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        let context = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
            .context(for: root)
        let inspector = FailOnSecondInventoryRevalidationInspector(
            store: context.failedHistoryStore
        )
        let events = PendingStoreEventLog()
        let journal = FakePendingRecordingJournal(events: events)
        let audio = FakePendingRecordingAudioFileSystem(events: events)
        let store = IOSPendingRecordingStore(
            journal: journal,
            audioFileSystem: audio,
            operationGate: context.operationGate,
            liveOwnerRegistry: context.pendingRecordingLiveOwnerRegistry,
            capabilityOwnerIdentity: context.ownerIdentity,
            storeIdentity: context.pendingRecordingStoreIdentity,
            repositoryGuard: context.repositoryGuard,
            failedHistoryMutationInterlock:
                context.failedHistoryMutationInterlock,
            failedOwnershipInspector: inspector,
            now: { Date(timeIntervalSince1970: 1_752_150_896.789) }
        )
        let preparation = try IOSPendingRecordingPreparation(
            attemptID: UUID(
                uuidString: "11234567-89AB-CDEF-8123-456789ABCDEF"
            )!,
            sourceArtifact: AudioRecordingArtifact(
                fileURL: URL(fileURLWithPath: "/runtime/source.m4a"),
                duration: 1.5,
                byteCount: 12
            ),
            initialState: .readyForTranscription,
            outputIntent: .standard,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "initial-model",
                language: .english,
                freeformPrompt: ""
            )
        )

        await #expect(throws: IOSPendingRecordingError.localRecoveryPending) {
            _ = try await store.prepare(preparation)
        }
        #expect(audio.publishCallCount == 1)
        #expect(audio.leaseReleaseCount == 1)
        #expect(journal.recording == nil)
    }

    @Test func failedRowAudioValidationSupportsDeleteWithNilOrUnrelatedPending()
        async throws {
        let setup = try PendingRowAudioValidationSetup()
        defer { setup.removeFiles() }
        let candidate = try failedHistoryTestEntry(index: 201)

        try await setup.context.operationGate.perform { lease in
            _ = try await setup.context.failedHistoryStore
                .mutateExactForTesting(
                    IOSFailedHistoryEnvelope(
                        revision: 1,
                        entries: [candidate],
                        audioCleanup: []
                    ),
                    operationLeaseAuthorization: lease
                )
            let authorization = try await setup.context.failedHistoryStore
                .prepareDelete(
                    attemptID: candidate.attemptID,
                    operationLeaseAuthorization: lease
                )

            for pending in [
                Optional<IOSPendingRecording>.none,
                try pendingRowAudioTestRecording(index: 202),
            ] {
                let journal = FakePendingRecordingJournal(
                    events: PendingStoreEventLog()
                )
                journal.recording = pending
                let audio = FakePendingRecordingAudioFileSystem(
                    events: PendingStoreEventLog()
                )
                let store = setup.makePendingStore(
                    journal: journal,
                    audio: audio
                )
                let validated = try await store
                    .acquireValidatedFailedHistoryRowAudio(
                        using: authorization,
                        operationLeaseAuthorization: lease
                    )

                #expect(validated.authorization == authorization)
                #expect(audio.leaseReleaseCount == 0)
                validated.release()
                #expect(audio.leaseReleaseCount == 1)
            }
        }
    }

    @Test func failedRowAudioValidationRejectsForeignAndStaleAuthority()
        async throws {
        let setup = try PendingRowAudioValidationSetup()
        defer { setup.removeFiles() }
        let candidate = try failedHistoryTestEntry(index: 211)
        let events = PendingStoreEventLog()
        let journal = FakePendingRecordingJournal(events: events)
        let audio = FakePendingRecordingAudioFileSystem(events: events)
        let store = setup.makePendingStore(journal: journal, audio: audio)

        let retained = try await setup.context.operationGate.perform { lease in
            _ = try await setup.context.failedHistoryStore
                .mutateExactForTesting(
                    IOSFailedHistoryEnvelope(
                        revision: 1,
                        entries: [candidate],
                        audioCleanup: []
                    ),
                    operationLeaseAuthorization: lease
                )
            let authorization = try await setup.context.failedHistoryStore
                .prepareDelete(
                    attemptID: candidate.attemptID,
                    operationLeaseAuthorization: lease
                )
            let foreign = setup.makePendingStore(
                journal: journal,
                audio: audio,
                storeIdentity: IOSPendingRecordingStoreIdentity()
            )
            await #expect(
                throws: IOSPendingRecordingError.localRecoveryPending
            ) {
                _ = try await foreign.acquireValidatedFailedHistoryRowAudio(
                    using: authorization,
                    operationLeaseAuthorization: lease
                )
            }
            #expect(audio.leaseReleaseCount == 0)
            return authorization
        }

        _ = try await setup.context.operationGate.perform { freshLease in
            await #expect(
                throws: IOSPendingRecordingError.localRecoveryPending
            ) {
                _ = try await store.acquireValidatedFailedHistoryRowAudio(
                    using: retained,
                    operationLeaseAuthorization: freshLease
                )
            }
        }
        #expect(audio.leaseReleaseCount == 0)
    }

    @Test func failedRowAudioValidationReleasesLeaseWhenPendingSourceChanges()
        async throws {
        let setup = try PendingRowAudioValidationSetup()
        defer { setup.removeFiles() }
        let candidate = try failedHistoryTestEntry(index: 221)
        let journal = FakePendingRecordingJournal(
            events: PendingStoreEventLog()
        )
        journal.recording = try pendingRowAudioTestRecording(index: 222)
        let audio = FakePendingRecordingAudioFileSystem(
            events: PendingStoreEventLog()
        )
        let store = setup.makePendingStore(journal: journal, audio: audio)

        try await setup.context.operationGate.perform { lease in
            _ = try await setup.context.failedHistoryStore
                .mutateExactForTesting(
                    IOSFailedHistoryEnvelope(
                        revision: 1,
                        entries: [candidate],
                        audioCleanup: []
                    ),
                    operationLeaseAuthorization: lease
                )
            let authorization = try await setup.context.failedHistoryStore
                .prepareDelete(
                    attemptID: candidate.attemptID,
                    operationLeaseAuthorization: lease
                )
            audio.onNextValidatedAudioAcquire {
                journal.recording = try? pendingRowAudioTestRecording(
                    index: 223
                )
            }

            await #expect(
                throws: IOSPendingRecordingError.localRecoveryPending
            ) {
                _ = try await store.acquireValidatedFailedHistoryRowAudio(
                    using: authorization,
                    operationLeaseAuthorization: lease
                )
            }
            #expect(audio.leaseReleaseCount == 1)
        }
    }

    @Test func failedRowAudioValidationSupportsRetentionCurrentPendingSource()
        async throws {
        let setup = try PendingRowAudioValidationSetup()
        defer { setup.removeFiles() }
        let entries = try (231...235).map {
            try failedHistoryTestEntry(index: $0)
        }
        let sortedEntries = IOSFailedHistoryValidation.sortedEntries(entries)
        let pending = try pendingRowAudioTestRecording(
            index: 236,
            phase: .awaitingRecovery
        )
        let pendingSnapshot = IOSPendingRecordingJournalMetadataSnapshot(
            testingRecording: pending,
            testingRevision: 2
        )
        let events = PendingStoreEventLog()
        let journal = FakePendingRecordingJournal(events: events)
        journal.recording = pending
        let audio = FakePendingRecordingAudioFileSystem(events: events)
        let store = setup.makePendingStore(journal: journal, audio: audio)
        let policyReceipt = try await pendingRowAudioPolicyReceipt(
            ownerIdentity: setup.context.ownerIdentity
        )

        try await setup.context.operationGate.perform { lease in
            _ = try await setup.context.failedHistoryStore
                .mutateExactForTesting(
                    IOSFailedHistoryEnvelope(
                        revision: 1,
                        entries: sortedEntries,
                        audioCleanup: []
                    ),
                    operationLeaseAuthorization: lease
                )
            let intendedRow = try failedRow(matching: pending)
            let preparationAudio = FakePendingRecordingAudioLease(
                relativeIdentifier: pending.audioRelativeIdentifier,
                artifact: AudioRecordingArtifact(
                    fileURL: URL(fileURLWithPath: "/protected/pending.m4a"),
                    duration: TimeInterval(pending.durationMilliseconds) / 1_000,
                    byteCount: pending.byteCount
                ),
                durationMilliseconds: pending.durationMilliseconds,
                events: PendingStoreEventLog(),
                onRelease: {}
            )
            let preparation = try #require(
                IOSPendingFailedHistoryTransferPreparation(
                    mint: IOSPendingFailedHistoryTransferPreparationMint(
                        testingToken: ()
                    ),
                    pendingSnapshot: pendingSnapshot,
                    intendedRow: intendedRow,
                    audioLease: preparationAudio,
                    pendingStoreIdentity:
                        setup.context.pendingRecordingStoreIdentity,
                    failedStoreIdentity:
                        setup.context.failedHistoryStore.storeIdentity,
                    ownerIdentity: setup.context.ownerIdentity,
                    repositoryBinding: setup.context.repositoryBinding,
                    operationLeaseAuthorization: lease,
                    policyReceipt: policyReceipt
                )
            )
            defer { preparation.releaseAudioLease() }
            let authorization = try #require(
                try await setup.context.failedHistoryStore.prepareRetention(
                    for: preparation
                )
            )
            let validated = try await store
                .acquireValidatedFailedHistoryRowAudio(
                    using: authorization,
                    operationLeaseAuthorization: lease
                )

            #expect(authorization.candidate == sortedEntries.last)
            #expect(
                authorization.purpose == .retention(preparation)
            )
            validated.release()
            #expect(audio.leaseReleaseCount == 1)
            #expect(
                events.values == [
                    "audio.inventory.validate",
                    "audio.validate",
                    "audio.inventory.validate",
                    "audio.lease.release",
                ]
            )
        }
    }

    @Test func failedAudioCleanupMintsExactRemovedAndAbsentReceipts()
        async throws {
        for disposition in [
            FakePendingRecordingAudioFileSystem.CleanupDisposition.removed,
            .alreadyAbsent,
        ] {
            let setup = try PendingRowAudioValidationSetup()
            defer { setup.removeFiles() }
            let tombstone = try failedHistoryTestAudioCleanup(index: 241)
            let journal = FakePendingRecordingJournal(
                events: PendingStoreEventLog()
            )
            let events = PendingStoreEventLog()
            let audio = FakePendingRecordingAudioFileSystem(events: events)
            audio.cleanupDisposition = disposition
            let store = setup.makePendingStore(
                journal: journal,
                audio: audio
            )

            try await setup.context.operationGate.perform { lease in
                _ = try await setup.context.failedHistoryStore
                    .mutateExactForTesting(
                        IOSFailedHistoryEnvelope(
                            revision: 1,
                            entries: [],
                            audioCleanup: [tombstone]
                        ),
                        operationLeaseAuthorization: lease
                    )
                let authorization = try #require(
                    try await setup.context.failedHistoryStore
                        .prepareNextAudioCleanup(
                            operationLeaseAuthorization: lease
                        )
                )
                let receipt = try await store
                    .reconcileFailedHistoryAudioCleanup(
                        using: authorization,
                        operationLeaseAuthorization: lease
                    )

                #expect(receipt.authorization == authorization)
                #expect(
                    receipt.issuerStoreIdentity
                        == setup.context.pendingRecordingStoreIdentity
                )
                switch (disposition, receipt.outcome) {
                case (.removed, .removed(let evidence)):
                    #expect(evidence.provesRemoval(of: authorization))
                case (.alreadyAbsent, .alreadyAbsent(let evidence)):
                    #expect(
                        evidence.provesPreexistingAbsence(
                            of: authorization
                        )
                    )
                default:
                    Issue.record("Unexpected cleanup receipt disposition")
                }
            }
            #expect(events.values == ["audio.cleanup"])
        }
    }

    @Test func failedAudioCleanupRejectsPendingSourceChangeAfterRemoval()
        async throws {
        let setup = try PendingRowAudioValidationSetup()
        defer { setup.removeFiles() }
        let tombstone = try failedHistoryTestAudioCleanup(index: 251)
        let journal = FakePendingRecordingJournal(
            events: PendingStoreEventLog()
        )
        journal.recording = try pendingRowAudioTestRecording(index: 252)
        let audio = FakePendingRecordingAudioFileSystem(
            events: PendingStoreEventLog()
        )
        let store = setup.makePendingStore(journal: journal, audio: audio)

        try await setup.context.operationGate.perform { lease in
            _ = try await setup.context.failedHistoryStore
                .mutateExactForTesting(
                    IOSFailedHistoryEnvelope(
                        revision: 1,
                        entries: [],
                        audioCleanup: [tombstone]
                    ),
                    operationLeaseAuthorization: lease
                )
            let authorization = try #require(
                try await setup.context.failedHistoryStore
                    .prepareNextAudioCleanup(
                        operationLeaseAuthorization: lease
                    )
            )
            audio.onCleanup {
                journal.recording = try? pendingRowAudioTestRecording(
                    index: 253
                )
            }
            await #expect(
                throws: IOSPendingRecordingError.localRecoveryPending
            ) {
                _ = try await store.reconcileFailedHistoryAudioCleanup(
                    using: authorization,
                    operationLeaseAuthorization: lease
                )
            }
        }
    }

    @Test func abandonedFailedAudioCleanupCannotReachFilesystem()
        async throws {
        let setup = try PendingRowAudioValidationSetup()
        defer { setup.removeFiles() }
        let tombstone = try failedHistoryTestAudioCleanup(index: 261)
        let events = PendingStoreEventLog()
        let journal = FakePendingRecordingJournal(events: events)
        let audio = FakePendingRecordingAudioFileSystem(events: events)
        let store = setup.makePendingStore(journal: journal, audio: audio)

        try await setup.context.operationGate.perform { lease in
            _ = try await setup.context.failedHistoryStore
                .mutateExactForTesting(
                    try IOSFailedHistoryEnvelope(
                        revision: 1,
                        entries: [],
                        audioCleanup: [tombstone]
                    ),
                    operationLeaseAuthorization: lease
                )
            let authorization = try #require(
                try await setup.context.failedHistoryStore
                    .prepareNextAudioCleanup(
                        operationLeaseAuthorization: lease
                    )
            )
            try await setup.context.failedHistoryStore
                .abandonPreparedAudioCleanup(
                    using: authorization,
                    operationLeaseAuthorization: lease
                )

            await #expect(
                throws: IOSPendingRecordingError.localRecoveryPending
            ) {
                _ = try await store.reconcileFailedHistoryAudioCleanup(
                    using: authorization,
                    operationLeaseAuthorization: lease
                )
            }
        }

        #expect(events.values.filter { $0 == "audio.cleanup" }.isEmpty)
    }

    @Test func journalFailurePreservesPublishedAudioAndReleasesItsCreatorLock() async {
        let fixture = StoreFixture()
        fixture.journal.createError = .journalWriteFailed

        await #expect(throws: IOSPendingRecordingError.journalWriteFailed) {
            _ = try await fixture.store.prepare(fixture.preparation())
        }

        #expect(fixture.audio.published)
        #expect(fixture.audio.leaseReleaseCount == 1)
        #expect(fixture.journal.recording == nil)
        #expect(!fixture.events.values.contains("audio.remove"))
    }

    @Test func uncertainBeginCommitCannotMintProviderAuthority() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        fixture.events.reset()
        fixture.journal.replaceError = .journalCommitUncertain
        fixture.journal.replaceCommitsBeforeError = true
        let transcriptionID = UUID()

        await #expect(
            throws: IOSPendingRecordingError.journalCommitUncertain
        ) {
            _ = try await fixture.store.beginTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: prepared),
                transcriptionID: transcriptionID
            )
        }

        let visibleCommit = try #require(fixture.journal.recording)
        #expect(visibleCommit.phase == .transcribing)
        #expect(visibleCommit.transcriptionID == transcriptionID)
        #expect(
            fixture.events.values == [
                "audio.validate",
                "journal.replace",
            ]
        )

        fixture.journal.replaceError = nil
        fixture.journal.replaceCommitsBeforeError = false
        let recovered = try await fixture.makeStore(
            destinationInspector: FakePendingDestinationInspector()
        ).recoverAfterProcessLoss(
            expected: IOSPendingRecordingCASExpectation(recording: visibleCommit)
        )
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)
    }

    @Test func liveFailedRetryBlocksPendingBeginAndRetryBeforeDurableWork()
        async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "pending-failed-retry-owner-\(UUID().uuidString)",
                isDirectory: true
            )
        let root = parent.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }

        let context = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
            .context(for: root)
        let retryState = context.failedHistoryRetryState
        let failedGate = IOSPersistenceOperationGate()
        let failedFileSystem = FailedHistoryFakeFileSystem()
        let failedStore = IOSFailedHistoryStore(
            journal: FoundationIOSFailedHistoryJournalRepository(
                fileSystem: failedFileSystem
            ),
            capabilityOwnerIdentity: context.ownerIdentity,
            operationGateIdentity: failedGate.identity,
            expectedPendingStoreIdentity:
                context.pendingRecordingStoreIdentity,
            retryLiveOwnerState: retryState,
            repositoryGuard: context.repositoryGuard
        )
        let operation = try failedHistoryTestRetryOperation(
            index: 801,
            state: .reserved
        )
        let row = try failedHistoryTestEntry(
            index: 801,
            retryCount: 1,
            retryOperation: operation
        )
        failedFileSystem.install(
            try IOSFailedHistoryWireCodec.encode(
                IOSFailedHistoryEnvelope(
                    revision: 1,
                    entries: [row],
                    audioCleanup: []
                )
            )
        )
        let token = try await failedGate.perform { lease in
            let token = try #require(
                try await failedStore.prepareRetryLiveOwnerToken(
                    operationLeaseAuthorization: lease
                )
            )
            #expect(await retryState.retainLiveOwner(token))
            return token
        }
        #expect(await retryState.hasLiveOwner())

        let beginFixture = StoreFixture(
            failedHistoryRetryState: retryState
        )
        let ready = try await beginFixture.store.prepare(
            beginFixture.preparation()
        )
        beginFixture.events.reset()
        await #expect(throws: IOSPendingRecordingError.localRecoveryPending) {
            _ = try await beginFixture.store.beginTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: ready),
                transcriptionID: UUID()
            )
        }
        #expect(beginFixture.journal.recording == ready)
        #expect(beginFixture.events.values.isEmpty)

        let retryFixture = StoreFixture(
            failedHistoryRetryState: retryState
        )
        let awaitingRecovery = try await retryFixture.store.prepare(
            retryFixture.preparation(initialState: .awaitingRecovery)
        )
        retryFixture.events.reset()
        await #expect(throws: IOSPendingRecordingError.localRecoveryPending) {
            _ = try await retryFixture.store.retryTranscription(
                expected: IOSPendingRecordingCASExpectation(
                    recording: awaitingRecovery
                ),
                transcriptionID: UUID(),
                transcriptionConfiguration: .defaults
            )
        }
        #expect(retryFixture.journal.recording == awaitingRecovery)
        #expect(retryFixture.events.values.isEmpty)
        #expect(await retryState.clearLiveOwner(token))
    }

    @Test func beginCommitsUUIDBeforeReturningOneOneShotAuthorization() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        fixture.events.reset()
        let transcriptionID = UUID()

        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: transcriptionID
        )

        let committed = try #require(fixture.journal.recording)
        #expect(committed.phase == .transcribing)
        #expect(committed.transcriptionID == transcriptionID)
        #expect(
            fixture.events.values == [
                "audio.validate",
                "journal.replace",
                "audio.validate",
            ]
        )
        let executor = CapturingPendingTranscriptionExecutor()
        #expect(try await handoff.execute(using: executor) == "transcript")
        #expect(executor.recording == committed)
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await handoff.execute(using: executor)
        }

        await #expect(throws: IOSPendingRecordingError.dispatchAlreadyCommitted) {
            _ = try await fixture.store.beginTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: committed),
                transcriptionID: transcriptionID
            )
        }
    }

    @Test func explicitRetryUsesFreshCompactConfigurationAndKeepsAttemptOwnership() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(
            fixture.preparation(initialState: .awaitingRecovery)
        )
        let transcriptionID = UUID()

        let handoff = try await fixture.store.retryTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: transcriptionID,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "retry-model",
                language: .japanese,
                freeformPrompt: "not durable"
            )
        )

        let executor = CapturingPendingTranscriptionExecutor()
        _ = try await handoff.execute(using: executor)
        let recording = try #require(executor.recording)
        #expect(recording.attemptID == prepared.attemptID)
        #expect(recording.createdAt == prepared.createdAt)
        #expect(recording.outputIntent == prepared.outputIntent)
        #expect(recording.durationMilliseconds == prepared.durationMilliseconds)
        #expect(recording.byteCount == prepared.byteCount)
        #expect(recording.transcriptionID == transcriptionID)
        #expect(recording.transcriptionModel == "retry-model")
        #expect(recording.transcriptionLanguageCode == "ja")
    }

    @Test func explicitRetryCanWidenReadyUsingFreshCompactConfiguration()
        async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(
            fixture.preparation(initialState: .readyForTranscription)
        )
        let transcriptionID = UUID()

        let handoff = try await fixture.store.retryTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: transcriptionID,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "ready-retry-model",
                language: .german,
                freeformPrompt: "runtime only"
            )
        )

        let executor = CapturingPendingTranscriptionExecutor()
        _ = try await handoff.execute(using: executor)
        let recording = try #require(executor.recording)
        #expect(recording.phase == .transcribing)
        #expect(recording.attemptID == prepared.attemptID)
        #expect(recording.audioRelativeIdentifier == prepared.audioRelativeIdentifier)
        #expect(recording.createdAt == prepared.createdAt)
        #expect(recording.outputIntent == prepared.outputIntent)
        #expect(recording.durationMilliseconds == prepared.durationMilliseconds)
        #expect(recording.byteCount == prepared.byteCount)
        #expect(recording.transcriptionID == transcriptionID)
        #expect(recording.transcriptionModel == "ready-retry-model")
        #expect(recording.transcriptionLanguageCode == "de")
    }

    @Test func providerAudioIsBoundedAndInvalidImmediatelyAfterExecution()
        async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let releaseCountBeforeExecution = fixture.audio.leaseReleaseCount
        let executor = ReadingPendingTranscriptionExecutor()

        #expect(try await handoff.execute(using: executor) == "transcript")

        #expect(executor.readBytes == Data(repeating: 0x5A, count: 8))
        #expect(
            fixture.audio.leaseReleaseCount
                == releaseCountBeforeExecution + 1
        )
        let retainedAudio = try #require(executor.audio)
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await retainedAudio.read(
                atOffset: 0,
                maximumByteCount: 1
            )
        }
    }

    @Test func providerAudioMapsRepositoryIdentityConflictExactly() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        fixture.audio.leaseReadError = .repositoryIdentityConflict
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let executor = ReadingPendingTranscriptionExecutor()

        await #expect(
            throws: IOSPendingRecordingError.repositoryIdentityConflict
        ) {
            _ = try await handoff.execute(using: executor)
        }

        #expect(fixture.events.values.contains("audio.lease.read"))
    }

    @Test func providerAudioEnforcesExact64KiBReadCeilingBeforeLeaseIO()
        async throws {
        #expect(IOSPendingTranscriptionAudio.maximumReadByteCount == 64 * 1_024)

        let allowedFixture = StoreFixture()
        let allowedPrepared = try await allowedFixture.store.prepare(
            allowedFixture.preparation(
                byteCount:
                    Int64(IOSPendingTranscriptionAudio.maximumReadByteCount + 8)
            )
        )
        let allowedHandoff = try await allowedFixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(
                recording: allowedPrepared
            ),
            transcriptionID: UUID()
        )
        let allowedExecutor = ReadingPendingTranscriptionExecutor(
            maximumByteCount: IOSPendingTranscriptionAudio.maximumReadByteCount
        )

        _ = try await allowedHandoff.execute(using: allowedExecutor)

        #expect(
            allowedExecutor.readBytes?.count
                == IOSPendingTranscriptionAudio.maximumReadByteCount
        )
        #expect(
            allowedFixture.events.values.contains("audio.lease.read")
        )

        let rejectedFixture = StoreFixture()
        let rejectedPrepared = try await rejectedFixture.store.prepare(
            rejectedFixture.preparation()
        )
        let rejectedHandoff = try await rejectedFixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(
                recording: rejectedPrepared
            ),
            transcriptionID: UUID()
        )
        rejectedFixture.events.reset()
        let rejectedExecutor = ReadingPendingTranscriptionExecutor(
            maximumByteCount:
                IOSPendingTranscriptionAudio.maximumReadByteCount + 1
        )

        await #expect(throws: IOSPendingRecordingError.linkedAudioInvalid) {
            _ = try await rejectedHandoff.execute(using: rejectedExecutor)
        }

        #expect(
            !rejectedFixture.events.values.contains("audio.lease.read")
        )
    }

    @Test func providerFailureInvalidatesAudioAndReleasesItsLease() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let releaseCountBeforeExecution = fixture.audio.leaseReleaseCount
        let executor = FailingPendingTranscriptionExecutor()

        do {
            _ = try await handoff.execute(using: executor)
            Issue.record("Expected the provider failure")
        } catch PendingTranscriptionExecutorTestError.failed {
        } catch {
            Issue.record("Expected the exact provider failure")
        }

        #expect(
            fixture.audio.leaseReleaseCount
                == releaseCountBeforeExecution + 1
        )
        let retainedAudio = try #require(executor.audio)
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await retainedAudio.read(
                atOffset: 0,
                maximumByteCount: 1
            )
        }
    }

    @Test func callerCancellationInvalidatesAudioAndReleasesItsLease()
        async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let releaseCountBeforeExecution = fixture.audio.leaseReleaseCount
        let probe = PendingExecutionProbe()
        let executor = CancellablePendingTranscriptionExecutor(probe: probe)
        let execution = Task {
            try await handoff.execute(using: executor)
        }
        await probe.waitUntilStarted()

        execution.cancel()

        await probe.waitUntilCancelled()
        switch await execution.result {
        case .success:
            Issue.record("Expected caller cancellation")
        case .failure(let error):
            #expect(error is CancellationError)
        }
        #expect(
            fixture.audio.leaseReleaseCount
                == releaseCountBeforeExecution + 1
        )
        let retainedAudio = try #require(executor.audio)
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await retainedAudio.read(
                atOffset: 0,
                maximumByteCount: 1
            )
        }
    }

    @Test func unconsumedHandoffDeinitInvalidatesAudioAndReleasesItsLease()
        async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let releaseCountBeforeHandoff = fixture.audio.leaseReleaseCount
        weak var releasedHandoff: IOSPendingTranscriptionHandoff?

        do {
            let handoff = try await fixture.store.beginTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: prepared),
                transcriptionID: UUID()
            )
            releasedHandoff = handoff
            #expect(releasedHandoff != nil)
        }

        #expect(releasedHandoff == nil)
        #expect(
            fixture.audio.leaseReleaseCount
                == releaseCountBeforeHandoff + 1
        )
    }

    @Test func postcommitHandoffFailureClearsDispatchIdentityBeforeReturning() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        fixture.events.reset()
        fixture.audio.validateError = .protectedAudioInvalid
        fixture.audio.validateErrorCallNumber = 2

        await #expect(throws: IOSPendingRecordingError.linkedAudioInvalid) {
            _ = try await fixture.store.beginTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: prepared),
                transcriptionID: UUID()
            )
        }

        let recovered = try #require(fixture.journal.recording)
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)
        #expect(
            fixture.events.values == [
                "audio.validate",
                "journal.replace",
                "audio.validate",
                "journal.replace",
            ]
        )
    }

    @Test func retryRejectsRetiredIdentityAndInvalidCurrentConfiguration() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let retiredID = UUID()
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: retiredID
        )
        let transcribing = try #require(fixture.journal.recording)
        let recovery = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )

        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await fixture.store.retryTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: recovery),
                transcriptionID: retiredID,
                transcriptionConfiguration: .defaults
            )
        }
        await #expect(
            throws: IOSPendingRecordingError.invalidTranscriptionConfiguration
        ) {
            _ = try await fixture.store.retryTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: recovery),
                transcriptionID: UUID(),
                transcriptionConfiguration: TranscriptionConfiguration(
                    language: .custom,
                    customLanguageCode: "invalid-language"
                )
            )
        }
        #expect(fixture.journal.recording == recovery)

        let freshID = UUID()
        let handoff = try await fixture.store.retryTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: recovery),
            transcriptionID: freshID,
            transcriptionConfiguration: .defaults
        )
        let executor = CapturingPendingTranscriptionExecutor()
        _ = try await handoff.execute(using: executor)
        #expect(executor.recording?.transcriptionID == freshID)
    }

    @Test func failedPostcommitCompensationKeepsAuthorityBlockedUntilRecovery() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        fixture.audio.validateError = .protectedAudioInvalid
        fixture.audio.validateErrorCallNumber = 2
        fixture.journal.replaceError = .journalWriteFailed
        fixture.journal.replaceErrorCallNumber = 2

        await #expect(throws: IOSPendingRecordingError.journalWriteFailed) {
            _ = try await fixture.store.beginTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: prepared),
                transcriptionID: UUID()
            )
        }

        let stranded = try #require(fixture.journal.recording)
        #expect(stranded.phase == .transcribing)
        #expect(stranded.transcriptionID != nil)
        fixture.journal.replaceError = nil
        let recovered = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: stranded)
        )
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)
    }

    @Test func transitionsUseExactCASAndClearLateResultIdentityBeforeRecovery() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let transcriptionID = UUID()
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: transcriptionID
        )
        let transcribing = try #require(fixture.journal.recording)

        let postProcessing = try await fixture.store.markPostProcessing(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )
        await #expect(throws: IOSPendingRecordingError.compareAndSwapFailed) {
            _ = try await fixture.store.markOutputDelivery(
                expected: IOSPendingRecordingCASExpectation(recording: transcribing)
            )
        }

        let recovery = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: postProcessing)
        )
        #expect(recovery.phase == .awaitingRecovery)
        #expect(recovery.transcriptionID == nil)
        await #expect(throws: IOSPendingRecordingError.compareAndSwapFailed) {
            _ = try await fixture.store.markOutputDelivery(
                expected: IOSPendingRecordingCASExpectation(recording: postProcessing)
            )
        }
    }

    @Test func recoveryRevokesAnUnconsumedHandoffBeforeRetry() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        let releaseCountBeforeRecovery = fixture.audio.leaseReleaseCount

        let recovery = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )
        #expect(
            fixture.audio.leaseReleaseCount
                == releaseCountBeforeRecovery + 1
        )

        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await handoff.execute(
                using: CapturingPendingTranscriptionExecutor()
            )
        }
        let retryHandoff = try await fixture.store.retryTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: recovery),
            transcriptionID: UUID(),
            transcriptionConfiguration: .defaults
        )
        #expect(
            try await retryHandoff.execute(
                using: CapturingPendingTranscriptionExecutor()
            ) == "transcript"
        )
    }

    @Test func processingCancellationCancelsRegisteredExecutionBeforeRecovery() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let releaseCountBeforeExecution = fixture.audio.leaseReleaseCount
        let transcribing = try #require(fixture.journal.recording)
        let probe = PendingExecutionProbe()
        let executor = CancellablePendingTranscriptionExecutor(probe: probe)
        let execution = Task {
            try await handoff.execute(using: executor)
        }
        await probe.waitUntilStarted()

        let recovery = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )

        #expect(recovery.phase == .awaitingRecovery)
        await probe.waitUntilCancelled()
        switch await execution.result {
        case .success:
            Issue.record("Expected registered execution cancellation")
        case .failure(let error):
            #expect(error is CancellationError)
        }
        #expect(
            fixture.audio.leaseReleaseCount
                == releaseCountBeforeExecution + 1
        )
        let retainedAudio = try #require(executor.audio)
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await retainedAudio.read(
                atOffset: 0,
                maximumByteCount: 1
            )
        }
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await handoff.execute(using: executor)
        }
    }

    @Test func recoveryDefersLeaseReleaseUntilInFlightReadFinishes()
        async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let readBarrier = PendingLeaseReadBarrier()
        fixture.audio.blockNextLeaseRead(with: readBarrier)
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        let releaseCountBeforeExecution = fixture.audio.leaseReleaseCount
        let executor = ReadingPendingTranscriptionExecutor()
        let execution = Task {
            try await handoff.execute(using: executor)
        }
        await readBarrier.waitUntilBlocked()
        defer {
            Task { await readBarrier.release() }
        }

        let recovery = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )

        #expect(recovery.phase == .awaitingRecovery)
        #expect(
            fixture.audio.leaseReleaseCount == releaseCountBeforeExecution
        )
        await readBarrier.release()
        switch await execution.result {
        case .success:
            Issue.record("A retired in-flight read must observe cancellation")
        case .failure(let error):
            #expect(error is CancellationError)
        }
        #expect(
            fixture.audio.leaseReleaseCount
                == releaseCountBeforeExecution + 1
        )
        let retainedAudio = try #require(executor.audio)
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await retainedAudio.read(
                atOffset: 0,
                maximumByteCount: 1
            )
        }
    }

    @Test func cancelledNoncooperativeLateSuccessIsRejected() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        let executor = NoncooperativePendingTranscriptionExecutor()
        let execution = Task {
            try await handoff.execute(using: executor)
        }
        #expect(executor.waitUntilStarted())
        defer { executor.release() }

        _ = try await fixture.store.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )
        executor.release()

        switch await execution.result {
        case .success:
            Issue.record("Cancelled late provider success must not escape")
        case .failure(let error):
            #expect(error is CancellationError)
        }
    }

    @Test func failedRecoveryWriteStillPermanentlyRevokesOldHandoff() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let handoff = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        fixture.journal.replaceError = .journalWriteFailed

        await #expect(throws: IOSPendingRecordingError.journalWriteFailed) {
            _ = try await fixture.store.markAwaitingRecovery(
                expected: IOSPendingRecordingCASExpectation(
                    recording: transcribing
                )
            )
        }

        #expect(fixture.journal.recording == transcribing)
        await #expect(
            throws: IOSPendingRecordingError.dispatchAlreadyCommitted
        ) {
            _ = try await handoff.execute(
                using: CapturingPendingTranscriptionExecutor()
            )
        }
        fixture.journal.replaceError = nil
        #expect(
            try await fixture.store.markAwaitingRecovery(
                expected: IOSPendingRecordingCASExpectation(
                    recording: transcribing
                )
            ).phase == .awaitingRecovery
        )
    }

    @Test func samePhaseAdvanceAlwaysConfirmsDurabilityAcrossStoreActors() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        fixture.journal.replaceError = .journalCommitUncertain
        fixture.journal.replaceCommitsBeforeError = true

        await #expect(
            throws: IOSPendingRecordingError.journalCommitUncertain
        ) {
            _ = try await fixture.store.markPostProcessing(
                expected: IOSPendingRecordingCASExpectation(
                    recording: transcribing
                )
            )
        }
        let visibleCommit = try #require(fixture.journal.recording)
        #expect(visibleCommit.phase == .postProcessing)

        fixture.journal.replaceError = nil
        fixture.events.reset()
        let secondStore = fixture.makeStore(
            destinationInspector: FakePendingDestinationInspector()
        )
        #expect(
            try await secondStore.markPostProcessing(
                expected: IOSPendingRecordingCASExpectation(
                    recording: visibleCommit
                )
            ) == visibleCommit
        )
        #expect(fixture.events.values == ["journal.replace"])

        fixture.events.reset()
        _ = try await fixture.store.markPostProcessing(
            expected: IOSPendingRecordingCASExpectation(recording: visibleCommit)
        )
        #expect(fixture.events.values == ["journal.replace"])
    }

    @Test func uncertainProcessRecoveryRetiresOldIdentityBeforeRetry() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let oldID = UUID()
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: oldID
        )
        let transcribing = try #require(fixture.journal.recording)
        let recoveringStore = fixture.makeStore(
            destinationInspector: FakePendingDestinationInspector()
        )
        fixture.journal.replaceError = .journalCommitUncertain
        fixture.journal.replaceCommitsBeforeError = true

        await #expect(
            throws: IOSPendingRecordingError.journalCommitUncertain
        ) {
            _ = try await recoveringStore.recoverAfterProcessLoss(
                expected: IOSPendingRecordingCASExpectation(
                    recording: transcribing
                )
            )
        }
        let visibleRecovery = try #require(fixture.journal.recording)
        #expect(visibleRecovery.phase == .awaitingRecovery)
        fixture.journal.replaceError = nil

        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await recoveringStore.retryTranscription(
                expected: IOSPendingRecordingCASExpectation(
                    recording: visibleRecovery
                ),
                transcriptionID: oldID,
                transcriptionConfiguration: .defaults
            )
        }
        let freshID = UUID()
        let handoff = try await recoveringStore.retryTranscription(
            expected: IOSPendingRecordingCASExpectation(
                recording: visibleRecovery
            ),
            transcriptionID: freshID,
            transcriptionConfiguration: .defaults
        )
        let executor = CapturingPendingTranscriptionExecutor()
        _ = try await handoff.execute(using: executor)
        #expect(executor.recording?.transcriptionID == freshID)
    }

    @Test func freshStoreRequiresDestinationAbsenceBeforeProcessLossRecovery() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        let transcriptionID = UUID()
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: transcriptionID
        )
        let transcribing = try #require(fixture.journal.recording)

        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await fixture.store.recoverAfterProcessLoss(
                expected: IOSPendingRecordingCASExpectation(recording: transcribing)
            )
        }

        let destination = FakePendingDestinationInspector()
        let freshStore = fixture.makeStore(destinationInspector: destination)
        let recovered = try await freshStore.recoverAfterProcessLoss(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)

        fixture.journal.recording = transcribing
        destination.hasDestination = true
        let blockedStore = fixture.makeStore(destinationInspector: destination)
        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await blockedStore.recoverAfterProcessLoss(
                expected: IOSPendingRecordingCASExpectation(recording: transcribing)
            )
        }

        fixture.journal.recording = transcribing
        destination.hasDestination = false
        destination.error = .journalUnreadable
        let failingStore = fixture.makeStore(destinationInspector: destination)
        await #expect(
            throws: IOSPendingRecordingError.destinationInspectionFailed
        ) {
            _ = try await failingStore.recoverAfterProcessLoss(
                expected: IOSPendingRecordingCASExpectation(recording: transcribing)
            )
        }
        #expect(fixture.journal.recording == transcribing)
        #expect(fixture.audio.published)
        #expect(destination.inspectionCallCount == 3)
    }

    @Test func outputDeliveryHappyPathIsIdempotentAndRecoverableAfterRelaunch() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        let postProcessing = try await fixture.store.markPostProcessing(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )
        let outputDelivery = try await fixture.store.markOutputDelivery(
            expected: IOSPendingRecordingCASExpectation(recording: postProcessing)
        )
        #expect(outputDelivery.phase == .outputDelivery)
        #expect(
            try await fixture.store.markOutputDelivery(
                expected: IOSPendingRecordingCASExpectation(recording: outputDelivery)
            ) == outputDelivery
        )

        let destination = FakePendingDestinationInspector()
        let relaunchedStore = fixture.makeStore(destinationInspector: destination)
        let recovered = try await relaunchedStore.recoverAfterProcessLoss(
            expected: IOSPendingRecordingCASExpectation(recording: outputDelivery)
        )
        #expect(recovered.phase == .awaitingRecovery)
        #expect(recovered.transcriptionID == nil)
    }

    @Test func containingAppCompletesExactAcceptedOutputAndResumesAudioFirstCrash()
        async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        let postProcessing = try await fixture.store.markPostProcessing(
            expected: IOSPendingRecordingCASExpectation(
                recording: transcribing
            )
        )
        let outputDelivery = try await fixture.store.markOutputDelivery(
            expected: IOSPendingRecordingCASExpectation(
                recording: postProcessing
            )
        )
        let destination = FakePendingDestinationInspector()
        destination.hasDestination = true
        let relaunchedStore = fixture.makeStore(
            destinationInspector: destination
        )
        fixture.journal.removeError = .journalRemoveFailed

        await #expect(throws: IOSPendingRecordingError.journalRemoveFailed) {
            _ = try await relaunchedStore
                .completeAcceptedOutputForContainingAppLaunchIfPresent()
        }
        #expect(!fixture.audio.published)
        #expect(fixture.journal.recording == outputDelivery)

        fixture.journal.removeError = nil
        #expect(
            try await relaunchedStore
                .completeAcceptedOutputForContainingAppLaunchIfPresent()
        )
        #expect(fixture.journal.recording == nil)
        #expect(
            fixture.events.values.contains("audio.accepted-output.remove")
        )
        #expect(fixture.events.values.contains("journal.metadata.remove"))
        #expect(!fixture.events.values.contains("audio.remove"))
        #expect(!fixture.events.values.contains("journal.remove"))
    }

    @Test func sameProcessLiveOwnerCannotClaimProcessLossRetirement()
        async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        let postProcessing = try await fixture.store.markPostProcessing(
            expected: IOSPendingRecordingCASExpectation(
                recording: transcribing
            )
        )
        let outputDelivery = try await fixture.store.markOutputDelivery(
            expected: IOSPendingRecordingCASExpectation(
                recording: postProcessing
            )
        )
        let destination = FakePendingDestinationInspector()
        destination.hasDestination = true
        let sameProcessStore = fixture.makeSameProcessStore(
            destinationInspector: destination
        )

        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await sameProcessStore
                .completeAcceptedOutputForContainingAppLaunchIfPresent()
        }
        #expect(fixture.journal.recording == outputDelivery)
        #expect(fixture.audio.published)
        #expect(
            !fixture.events.values.contains("audio.accepted-output.remove")
        )
    }

    @Test func freshProcessRegistryCanUseExactForegroundRetirementPath()
        async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        _ = try await fixture.store.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)
        let postProcessing = try await fixture.store.markPostProcessing(
            expected: IOSPendingRecordingCASExpectation(
                recording: transcribing
            )
        )
        let outputDelivery = try await fixture.store.markOutputDelivery(
            expected: IOSPendingRecordingCASExpectation(
                recording: postProcessing
            )
        )
        let freshGate = IOSPersistenceOperationGate()
        let freshOwner = IOSAcceptedHistoryCapabilityOwnerIdentity()
        let freshStoreIdentity = IOSPendingRecordingStoreIdentity()
        let deliveryStoreIdentity = IOSAcceptedOutputDeliveryStoreIdentity()
        let freshStore = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            operationGate: freshGate,
            liveOwnerRegistry: IOSPendingRecordingLiveOwnerRegistry(),
            capabilityOwnerIdentity: freshOwner,
            storeIdentity: freshStoreIdentity
        )
        let timestamp = outputDelivery.updatedAt
        let record = try IOSAcceptedOutputDeliveryRecord(
            revision: 1,
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: outputDelivery.attemptID,
            transcriptID: try #require(outputDelivery.transcriptionID),
            acceptedText: "accepted",
            outputIntent: outputDelivery.outputIntent,
            createdAt: timestamp,
            updatedAt: timestamp,
            expiresAt: timestamp.addingTimeInterval(86_400),
            deliveryState: .pending,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: true,
            publicationGeneration: 0,
            historyWrite: nil
        )

        try await freshGate.perform { lease in
            let destination = IOSForegroundVoiceAcceptedDestinationAuthorization(
                record: record,
                snapshot: IOSAcceptedOutputDeliveryJournalSnapshot(
                    record: record,
                    fileRevision: IOSStrictProtectedRecordFileRevision(
                        testingToken: 1
                    )
                ),
                storeIdentity: deliveryStoreIdentity,
                ownerIdentity: freshOwner,
                operationLeaseAuthorization: lease
            )
            let audioRemoval = try await freshStore
                .removeForegroundVoiceAcceptedOutputAudioAfterProcessLoss(
                    expected: outputDelivery,
                    destinationAuthorization: destination,
                    deliveryStoreIdentity: deliveryStoreIdentity,
                    operationLeaseAuthorization: lease
                )
            try await freshStore.retireForegroundVoiceAcceptedOutputJournal(
                expected: outputDelivery,
                destinationAuthorization: destination,
                audioRemovalAuthorization: audioRemoval,
                deliveryStoreIdentity: deliveryStoreIdentity,
                operationLeaseAuthorization: lease
            )
        }

        #expect(fixture.journal.recording == nil)
        #expect(!fixture.audio.published)
        #expect(
            fixture.events.values.contains("audio.accepted-output.remove")
        )
        #expect(fixture.events.values.contains("journal.metadata.remove"))
    }

    @Test func foregroundJournalAbsenceProofIsRootStoreOwnerAndLeaseBound()
        async throws {
        let fixture = StoreFixture()

        let captured = try await fixture.operationGate.perform { lease in
            let proof = try await fixture.store
                .proveForegroundVoicePendingJournalAbsent(
                    operationLeaseAuthorization: lease
                )
            #expect(
                proof.provesAbsence(
                    issuerStoreIdentity: fixture.storeIdentity,
                    ownerIdentity: fixture.capabilityOwnerIdentity,
                    operationLeaseAuthorization: lease
                )
            )
            #expect(
                proof.description
                    == "IOSForegroundVoicePendingJournalAbsenceAuthorization(redacted)"
            )
            #expect(proof.customMirror.children.isEmpty)
            return (proof, lease)
        }

        #expect(
            !captured.0.provesAbsence(
                issuerStoreIdentity: fixture.storeIdentity,
                ownerIdentity: fixture.capabilityOwnerIdentity,
                operationLeaseAuthorization: captured.1
            )
        )
        #expect(fixture.events.values == ["journal.metadata.absence"])
    }

    @Test func publicDestinationProofReceivesExactDurableIdentity() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "holdtype-pending-store-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let attemptID = UUID()
        let transcriptionID = UUID()
        let timestamp = try IOSPendingRecordingTimestampCodec.canonicalDate(
            from: Date()
        )
        let recording = try IOSPendingRecording(
            attemptID: attemptID,
            audioRelativeIdentifier: IOSPendingRecordingStorageLocation
                .relativeAudioIdentifier(for: attemptID, format: .wav),
            createdAt: timestamp,
            updatedAt: timestamp,
            phase: .outputDelivery,
            outputIntent: .standard,
            transcriptionID: transcriptionID,
            transcriptionModel: TranscriptionConfiguration.defaultModel,
            transcriptionLanguageCode: nil,
            durationMilliseconds: 1_000,
            byteCount: 1_000
        )
        try FoundationIOSPendingRecordingJournalRepository(
            applicationSupportDirectoryURL: directoryURL
        ).create(recording)
        try await clearProductionRetryRecoveryBarrier(at: directoryURL)
        let capture = PublicDestinationProofCapture()
        let store = IOSPendingRecordingStore(
            applicationSupportDirectoryURL: directoryURL,
            canonicalDestinationExists: { attemptID, transcriptionID in
                capture.record(
                    attemptID: attemptID,
                    transcriptionID: transcriptionID
                )
                return false
            }
        )

        let recovered = try await store.recoverAfterProcessLoss(
            expected: IOSPendingRecordingCASExpectation(recording: recording)
        )

        #expect(recovered.phase == .awaitingRecovery)
        #expect(capture.attemptID == attemptID)
        #expect(capture.transcriptionID == transcriptionID)
    }

    @Test func productionDestinationInspectorConfirmsAbsentAndUnrelatedState()
        throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "pending-destination-proof-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let context = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
            .context(for: root)
        let inspector = IOSPendingRecordingProductionDestinationInspector(
            applicationSupportDirectoryURL: root,
            repositoryGuard: context.repositoryGuard
        )
        let attemptID = UUID()
        let transcriptionID = UUID()
        let timestamp = try IOSPendingRecordingTimestampCodec.canonicalDate(
            from: Date(timeIntervalSince1970: 1_752_150_896.789)
        )
        let recording = try IOSPendingRecording(
            attemptID: attemptID,
            audioRelativeIdentifier: IOSPendingRecordingStorageLocation
                .relativeAudioIdentifier(for: attemptID, format: .m4a),
            createdAt: timestamp,
            updatedAt: timestamp,
            phase: .outputDelivery,
            outputIntent: .standard,
            transcriptionID: transcriptionID,
            transcriptionModel: TranscriptionConfiguration.defaultModel,
            transcriptionLanguageCode: nil,
            durationMilliseconds: 1_000,
            byteCount: 1_000
        )
        let expectedRoot = context.repositoryBinding.physicalRootIdentity

        #expect(
            try inspector.inspectCanonicalDestination(
                for: recording,
                expectedRepositoryRoot: expectedRoot
            ) == .provenAbsent
        )

        let deliveryJournal =
            FoundationIOSAcceptedOutputDeliveryJournalRepository(
                applicationSupportDirectoryURL: root,
                repositoryGuard: context.repositoryGuard
            )
        let unrelated = try IOSAcceptedOutputDeliveryRecord(
            revision: 1,
            deliveryID: UUID(),
            sessionID: UUID(),
            attemptID: UUID(),
            transcriptID: UUID(),
            acceptedText: "unrelated",
            outputIntent: .standard,
            createdAt: timestamp,
            updatedAt: timestamp,
            expiresAt: timestamp.addingTimeInterval(86_400),
            deliveryState: .pending,
            automaticInsertionPreferenceEnabled: false,
            keepLatestResult: true,
            publicationGeneration: 0,
            historyWrite: nil
        )
        let before = try deliveryJournal.create(unrelated)

        #expect(
            try inspector.inspectCanonicalDestination(
                for: recording,
                expectedRepositoryRoot: expectedRoot
            ) == .provenAbsent
        )
        let after = try #require(try deliveryJournal.load())
        #expect(after.record == unrelated)
        #expect(after.fileRevision != before.fileRevision)
    }

    @Test func loadNeverExposesAudioURLAndDistinguishesOrphanAndAvailability() async throws {
        let empty = StoreFixture()
        #expect(try await empty.store.load() == nil)

        empty.audio.requireEmptyError = .namespaceNotEmpty
        await #expect(throws: IOSPendingRecordingError.orphanedAudio) {
            _ = try await empty.store.load()
        }

        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(fixture.preparation())
        fixture.audio.validateError = .protectedAudioMissing
        let observation = try #require(try await fixture.store.load())
        #expect(observation.recording == prepared)
        #expect(observation.availability == .missing)
        #expect(!String(describing: observation).contains("protected"))
    }

    @Test func sharedLiveOwnerRegistryBlocksRecoveryUntilProcessLoss() async throws {
        let fixture = StoreFixture()
        let registry = IOSPendingRecordingLiveOwnerRegistry()
        let destination = FakePendingDestinationInspector()
        let owner = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            liveOwnerRegistry: registry,
            now: { fixture.clockDate }
        )
        let secondStore = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            destinationInspector: destination,
            liveOwnerRegistry: registry,
            now: { fixture.clockDate }
        )
        let prepared = try await owner.prepare(fixture.preparation())
        _ = try await owner.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: UUID()
        )
        let transcribing = try #require(fixture.journal.recording)

        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await secondStore.recoverAfterProcessLoss(
                expected: IOSPendingRecordingCASExpectation(recording: transcribing)
            )
        }

        let relaunchedStore = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            destinationInspector: destination,
            liveOwnerRegistry: IOSPendingRecordingLiveOwnerRegistry(),
            now: { fixture.clockDate }
        )
        let recovered = try await relaunchedStore.recoverAfterProcessLoss(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )
        #expect(recovered.phase == .awaitingRecovery)
    }

    @Test func retiredIdentityIsRejectedAcrossStoresInTheSameProcess() async throws {
        let fixture = StoreFixture()
        let registry = IOSPendingRecordingLiveOwnerRegistry()
        let owner = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            liveOwnerRegistry: registry,
            now: { fixture.clockDate }
        )
        let secondStore = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            liveOwnerRegistry: registry,
            now: { fixture.clockDate }
        )
        let prepared = try await owner.prepare(fixture.preparation())
        let retiredID = UUID()
        _ = try await owner.beginTranscription(
            expected: IOSPendingRecordingCASExpectation(recording: prepared),
            transcriptionID: retiredID
        )
        let transcribing = try #require(fixture.journal.recording)
        let recovery = try await owner.markAwaitingRecovery(
            expected: IOSPendingRecordingCASExpectation(recording: transcribing)
        )

        await #expect(throws: IOSPendingRecordingError.invalidTransition) {
            _ = try await secondStore.retryTranscription(
                expected: IOSPendingRecordingCASExpectation(recording: recovery),
                transcriptionID: retiredID,
                transcriptionConfiguration: .defaults
            )
        }
    }

    @Test func discardRemovesAudioBeforeJournalAndKeepsJournalOnAudioFailure() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(
            fixture.preparation(initialState: .awaitingRecovery)
        )
        fixture.events.reset()

        #expect(
            try await fixture.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: prepared)
            ) == .discarded
        )
        #expect(
            fixture.events.values == [
                "audio.accepted-output.remove",
                "journal.metadata.remove",
            ]
        )
        #expect(fixture.journal.recording == nil)
        #expect(
            try await fixture.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: prepared)
            ) == .alreadyAbsent
        )

        let failing = StoreFixture()
        let retained = try await failing.store.prepare(
            failing.preparation(initialState: .awaitingRecovery)
        )
        failing.audio.removeError = .removeFailed
        await #expect(throws: IOSPendingRecordingError.audioRemoveFailed) {
            _ = try await failing.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: retained)
            )
        }
        #expect(failing.journal.recording == retained)
        #expect(!failing.events.values.contains("journal.metadata.remove"))
    }

    @Test func processGatePreventsTwoStoresFromPublishingTheSameSlot() async {
        let fixture = StoreFixture()
        let publishBarrier = PendingStorePublishBarrier()
        let gateProbe = PendingStoreGateProbe()
        let sharedGate = IOSPendingRecordingOperationGate { event in
            gateProbe.record(event)
        }
        fixture.audio.blockNextPublish(with: publishBarrier)
        let firstStore = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            operationGate: sharedGate,
            now: { fixture.clockDate }
        )
        let secondStore = IOSPendingRecordingStore(
            journal: fixture.journal,
            audioFileSystem: fixture.audio,
            operationGate: sharedGate,
            now: { fixture.clockDate }
        )
        let firstPreparation = fixture.preparation(attemptID: UUID())
        let secondPreparation = fixture.preparation(attemptID: UUID())

        let firstTask = Task { try? await firstStore.prepare(firstPreparation) }
        #expect(publishBarrier.waitUntilBlocked())
        let secondTask = Task { try? await secondStore.prepare(secondPreparation) }
        #expect(gateProbe.waitUntilEnqueued())
        publishBarrier.release()
        let results = await [firstTask.value, secondTask.value]

        #expect(results.compactMap { $0 }.count == 1)
        #expect(fixture.audio.publishCallCount == 1)
        #expect(fixture.journal.recording != nil)
    }

    @Test func discardResumesAfterAudioFirstCrashWithoutGuessingOrphans() async throws {
        let fixture = StoreFixture()
        let prepared = try await fixture.store.prepare(
            fixture.preparation(initialState: .awaitingRecovery)
        )
        fixture.journal.removeError = .journalRemoveFailed

        await #expect(throws: IOSPendingRecordingError.journalRemoveFailed) {
            _ = try await fixture.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: prepared)
            )
        }
        #expect(!fixture.audio.published)
        #expect(fixture.journal.recording == prepared)

        fixture.journal.removeError = nil
        #expect(
            try await fixture.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: prepared)
            ) == .discarded
        )
        #expect(fixture.journal.recording == nil)

        let orphan = StoreFixture()
        _ = try await orphan.store.prepare(
            orphan.preparation(initialState: .awaitingRecovery)
        )
        orphan.journal.recording = nil
        orphan.events.reset()
        await #expect(throws: IOSPendingRecordingError.orphanedAudio) {
            _ = try await orphan.store.discard(
                expected: IOSPendingRecordingCASExpectation(recording: prepared)
            )
        }
        #expect(
            orphan.events.values == [
                "journal.metadata.absence",
                "audio.namespace.empty",
            ]
        )
        #expect(orphan.audio.published)
    }
}

private func clearProductionRetryRecoveryBarrier(at root: URL) async throws {
    let coordinator = IOSAcceptedHistoryCoordinator(
        applicationSupportDirectoryURL: root
    )
    #expect(
        try await coordinator.recoverInterruptedFailedHistoryRetry()
            == .noWork
    )
}

private final class PendingRowAudioValidationSetup: @unchecked Sendable {
    let parent: URL
    let context: IOSAcceptedHistoryCoordinatorProcessContext

    init() throws {
        parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "pending-row-audio-\(UUID().uuidString)",
                isDirectory: true
            )
        let root = parent.appendingPathComponent(
            "ApplicationSupport",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        context = IOSAcceptedHistoryCoordinatorProcessContextRegistry()
            .context(for: root)
    }

    func makePendingStore(
        journal: FakePendingRecordingJournal,
        audio: FakePendingRecordingAudioFileSystem,
        storeIdentity: IOSPendingRecordingStoreIdentity? = nil
    ) -> IOSPendingRecordingStore {
        IOSPendingRecordingStore(
            journal: journal,
            audioFileSystem: audio,
            operationGate: context.operationGate,
            liveOwnerRegistry: context.pendingRecordingLiveOwnerRegistry,
            capabilityOwnerIdentity: context.ownerIdentity,
            storeIdentity:
                storeIdentity ?? context.pendingRecordingStoreIdentity,
            repositoryGuard: context.repositoryGuard,
            failedHistoryMutationInterlock:
                context.failedHistoryMutationInterlock,
            failedOwnershipInspector: context.failedHistoryStore,
            now: { Date(timeIntervalSince1970: 1_752_150_896.789) }
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: parent)
    }
}

private func pendingRowAudioTestRecording(
    index: Int,
    phase: IOSPendingRecordingPhase = .readyForTranscription
) throws -> IOSPendingRecording {
    let attemptID = failedHistoryTestUUID(namespace: 0x71, index: index)
    return try IOSPendingRecording(
        attemptID: attemptID,
        audioRelativeIdentifier:
            IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
                for: attemptID,
                format: .m4a
            ),
        createdAt: try failedHistoryTestDate(
            offsetMilliseconds: Int64(index * 10)
        ),
        updatedAt: try failedHistoryTestDate(
            offsetMilliseconds: Int64(index * 10 + 2)
        ),
        phase: phase,
        outputIntent: .standard,
        transcriptionID: nil,
        transcriptionModel: "gpt-4o-mini-transcribe",
        transcriptionLanguageCode: "en",
        durationMilliseconds: 1_250,
        byteCount: 4_096
    )
}

private func failedRow(
    matching pending: IOSPendingRecording
) throws -> IOSFailedHistoryEntry {
    try IOSFailedHistoryEntry(
        attemptID: pending.attemptID,
        createdAt: pending.createdAt,
        updatedAt: pending.updatedAt,
        policyGeneration: 1,
        failureCategory: .networkFailure,
        pipelineStage: .transcription,
        retryCount: 0,
        outputIntent: pending.outputIntent,
        transcriptionModel: pending.transcriptionModel,
        transcriptionLanguageCode: pending.transcriptionLanguageCode,
        durationMilliseconds: pending.durationMilliseconds,
        byteCount: pending.byteCount,
        audioRelativeIdentifier: pending.audioRelativeIdentifier,
        ownershipState: .pendingJournalRetirement,
        retryOperation: nil
    )
}

private func pendingRowAudioPolicyReceipt(
    ownerIdentity: IOSAcceptedHistoryCapabilityOwnerIdentity
) async throws -> IOSHistoryPolicyReceipt {
    let state = try IOSHistoryPolicyState(
        revision: 1,
        historyEnabled: true,
        policyGeneration: 1
    )
    let store = IOSHistoryPolicyStore(
        journal: PendingRowAudioPolicyJournal(state: state),
        capabilityOwnerIdentity: ownerIdentity
    )
    return try await store.confirm(
        expected: IOSHistoryPolicyExpectation(state: state)
    )
}

private struct PendingRowAudioPolicyJournal:
    IOSHistoryPolicyJournalStoring {
    let state: IOSHistoryPolicyState

    func load() throws -> IOSHistoryPolicyJournalSnapshot? {
        IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: 1
            )
        )
    }

    func replace(
        _ state: IOSHistoryPolicyState,
        expected: IOSHistoryPolicyJournalSnapshot
    ) throws -> IOSHistoryPolicyJournalSnapshot {
        guard expected.state == self.state,
              state == self.state else {
            throw IOSHistoryPolicyError.compareAndSwapFailed
        }
        return IOSHistoryPolicyJournalSnapshot(
            state: state,
            fileRevision: IOSStrictProtectedRecordFileRevision(
                testingToken: 2
            )
        )
    }

    func performStagingMaintenance(
        now: Date
    ) throws -> IOSStrictProtectedRecordMaintenanceReport {
        _ = now
        return .empty
    }
}

private final class StoreFixture: @unchecked Sendable {
    let events = PendingStoreEventLog()
    let journal: FakePendingRecordingJournal
    let audio: FakePendingRecordingAudioFileSystem
    let clockDate = Date(timeIntervalSince1970: 1_752_150_896.789)
    let operationGate = IOSPersistenceOperationGate()
    let liveOwnerRegistry = IOSPendingRecordingLiveOwnerRegistry()
    let capabilityOwnerIdentity =
        IOSAcceptedHistoryCapabilityOwnerIdentity()
    let storeIdentity = IOSPendingRecordingStoreIdentity()
    let failedHistoryRetryState: IOSFailedHistoryRetryLiveOwnerState
    let store: IOSPendingRecordingStore

    init(
        failedHistoryRetryState: IOSFailedHistoryRetryLiveOwnerState =
            IOSFailedHistoryRetryLiveOwnerState()
    ) {
        let events = events
        self.failedHistoryRetryState = failedHistoryRetryState
        journal = FakePendingRecordingJournal(events: events)
        audio = FakePendingRecordingAudioFileSystem(events: events)
        store = IOSPendingRecordingStore(
            journal: journal,
            audioFileSystem: audio,
            operationGate: operationGate,
            liveOwnerRegistry: liveOwnerRegistry,
            failedHistoryRetryState: failedHistoryRetryState,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            storeIdentity: storeIdentity,
            now: { Date(timeIntervalSince1970: 1_752_150_896.789) }
        )
    }

    func makeStore(
        destinationInspector: any IOSPendingRecordingDestinationInspecting
    ) -> IOSPendingRecordingStore {
        IOSPendingRecordingStore(
            journal: journal,
            audioFileSystem: audio,
            destinationInspector: destinationInspector,
            failedHistoryRetryState: failedHistoryRetryState,
            now: { self.clockDate }
        )
    }

    func makeSameProcessStore(
        destinationInspector: any IOSPendingRecordingDestinationInspecting
    ) -> IOSPendingRecordingStore {
        IOSPendingRecordingStore(
            journal: journal,
            audioFileSystem: audio,
            destinationInspector: destinationInspector,
            operationGate: operationGate,
            liveOwnerRegistry: liveOwnerRegistry,
            failedHistoryRetryState: failedHistoryRetryState,
            capabilityOwnerIdentity: capabilityOwnerIdentity,
            storeIdentity: storeIdentity,
            now: { self.clockDate }
        )
    }

    func preparation(
        attemptID: UUID = UUID(
            uuidString: "01234567-89AB-CDEF-8123-456789ABCDEF"
        )!,
        initialState: IOSPendingRecordingInitialState = .readyForTranscription,
        byteCount: Int64 = 12
    ) -> IOSPendingRecordingPreparation {
        try! IOSPendingRecordingPreparation(
            attemptID: attemptID,
            sourceArtifact: AudioRecordingArtifact(
                fileURL: URL(fileURLWithPath: "/runtime/source.m4a"),
                duration: 1.5,
                byteCount: byteCount
            ),
            initialState: initialState,
            outputIntent: .translate,
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "initial-model",
                language: .english,
                freeformPrompt: "not durable"
            )
        )
    }
}

private final class FailOnSecondInventoryRevalidationInspector:
    IOSPendingRecordingFailedOwnershipInspecting,
    @unchecked Sendable {
    private let lock = NSLock()
    private let store: IOSFailedHistoryStore
    private var revalidationCount = 0

    var failedStoreIdentity: IOSFailedHistoryStoreIdentity {
        store.failedStoreIdentity
    }

    init(store: IOSFailedHistoryStore) {
        self.store = store
    }

    func sealProtectedAudioInventory(
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryProtectedAudioInventory {
        try await store.sealProtectedAudioInventory(
            expectedPendingStoreIdentity: expectedPendingStoreIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func revalidateProtectedAudioInventory(
        _ inventory: IOSFailedHistoryProtectedAudioInventory,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws {
        let count = lock.withLock {
            revalidationCount += 1
            return revalidationCount
        }
        if count == 2 {
            throw IOSFailedHistoryError.compareAndSwapFailed
        }
        try await store.revalidateProtectedAudioInventory(
            inventory,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }

    func provePendingOwnershipAbsent(
        for pendingKey: IOSFailedHistoryPendingOwnershipKey,
        expectedPendingStoreIdentity: IOSPendingRecordingStoreIdentity,
        operationLeaseAuthorization:
            IOSPersistenceOperationLeaseAuthorization
    ) async throws -> IOSFailedHistoryPendingOwnershipAbsenceProof {
        try await store.provePendingOwnershipAbsent(
            for: pendingKey,
            expectedPendingStoreIdentity: expectedPendingStoreIdentity,
            operationLeaseAuthorization: operationLeaseAuthorization
        )
    }
}

private final class FakePendingRecordingJournal:
    IOSPendingRecordingJournalStoring,
    @unchecked Sendable {
    private let lock = NSLock()
    private let events: PendingStoreEventLog
    private var storedRecording: IOSPendingRecording?
    private var storedRevision: UInt64 = 1
    private var storedCreateError: IOSPendingRecordingError?
    private var storedReplaceError: IOSPendingRecordingError?
    private var storedReplaceErrorCallNumber: Int?
    private var storedReplaceCommitsBeforeError = false
    private var storedReplaceCallCount = 0
    private var storedRemoveError: IOSPendingRecordingError?

    var recording: IOSPendingRecording? {
        get { lock.withLock { storedRecording } }
        set {
            lock.withLock {
                storedRecording = newValue
                storedRevision &+= 1
            }
        }
    }

    var createError: IOSPendingRecordingError? {
        get { lock.withLock { storedCreateError } }
        set { lock.withLock { storedCreateError = newValue } }
    }
    var replaceError: IOSPendingRecordingError? {
        get { lock.withLock { storedReplaceError } }
        set { lock.withLock { storedReplaceError = newValue } }
    }
    var replaceErrorCallNumber: Int? {
        get { lock.withLock { storedReplaceErrorCallNumber } }
        set { lock.withLock { storedReplaceErrorCallNumber = newValue } }
    }
    var replaceCommitsBeforeError: Bool {
        get { lock.withLock { storedReplaceCommitsBeforeError } }
        set { lock.withLock { storedReplaceCommitsBeforeError = newValue } }
    }
    var removeError: IOSPendingRecordingError? {
        get { lock.withLock { storedRemoveError } }
        set { lock.withLock { storedRemoveError = newValue } }
    }

    init(events: PendingStoreEventLog) {
        self.events = events
    }

    func load() throws -> IOSPendingRecording? {
        lock.withLock { storedRecording }
    }

    func loadMetadataSnapshot(
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataSnapshot? {
        _ = authorization
        return lock.withLock {
            storedRecording.map {
                IOSPendingRecordingJournalMetadataSnapshot(
                    testingRecording: $0,
                    testingRevision: storedRevision
                )
            }
        }
    }

    func create(_ recording: IOSPendingRecording) throws {
        events.append("journal.create")
        try lock.withLock {
            if let storedCreateError {
                throw storedCreateError
            }
            guard storedRecording == nil else {
                throw IOSPendingRecordingError.pendingSlotOccupied
            }
            storedRecording = recording
            storedRevision &+= 1
        }
    }

    func replace(
        _ recording: IOSPendingRecording,
        expected: IOSPendingRecording
    ) throws {
        events.append("journal.replace")
        try lock.withLock {
            storedReplaceCallCount += 1
            guard storedRecording == expected else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            if let storedReplaceError,
               storedReplaceErrorCallNumber == nil
                || storedReplaceErrorCallNumber == storedReplaceCallCount {
                if storedReplaceCommitsBeforeError {
                    storedRecording = recording
                    storedRevision &+= 1
                }
                throw storedReplaceError
            }
            storedRecording = recording
            storedRevision &+= 1
        }
    }

    func remove(expected: IOSPendingRecording) throws -> Bool {
        events.append("journal.remove")
        return try lock.withLock {
            if let storedRemoveError {
                throw storedRemoveError
            }
            guard let storedRecording else {
                return false
            }
            guard storedRecording == expected else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            self.storedRecording = nil
            storedRevision &+= 1
            return true
        }
    }

    func removeMetadata(
        expected: IOSPendingRecordingJournalMetadataSnapshot,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        _ = authorization
        events.append("journal.metadata.remove")
        return try lock.withLock {
            if let storedRemoveError {
                throw storedRemoveError
            }
            guard let storedRecording,
                  IOSPendingRecordingJournalMetadataSnapshot(
                      testingRecording: storedRecording,
                      testingRevision: storedRevision
                  ) == expected else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            self.storedRecording = nil
            storedRevision &+= 1
            return IOSPendingRecordingJournalMetadataAbsenceEvidence(
                testingRemoved: expected,
                repositoryRoot: expectedRepositoryRoot
                    ?? IOSPersistenceRepositoryRootIdentity(
                        device: 1,
                        inode: 1
                    )
            )
        }
    }

    func proveMetadataAbsent(
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?,
        authorization: IOSPendingRecordingMetadataRetirementAuthorization
    ) throws -> IOSPendingRecordingJournalMetadataAbsenceEvidence {
        _ = authorization
        events.append("journal.metadata.absence")
        return try lock.withLock {
            guard storedRecording == nil else {
                throw IOSPendingRecordingError.compareAndSwapFailed
            }
            return IOSPendingRecordingJournalMetadataAbsenceEvidence(
                testingAlreadyAbsentRepositoryRoot: expectedRepositoryRoot
                    ?? IOSPersistenceRepositoryRootIdentity(
                        device: 1,
                        inode: 1
                    )
            )
        }
    }
}

private final class FakePendingRecordingAudioFileSystem:
    IOSPendingRecordingAudioFileSystem,
    @unchecked Sendable {
    enum CleanupDisposition: Sendable {
        case removed
        case alreadyAbsent
    }

    private let lock = NSLock()
    private let events: PendingStoreEventLog
    private var storedPublished = false
    private var storedPublishCallCount = 0
    private var storedLeaseReleaseCount = 0
    private var storedRequireEmptyError: IOSPendingRecordingAudioFileSystemError?
    private var storedValidateError: IOSPendingRecordingAudioFileSystemError?
    private var storedValidateErrorCallNumber: Int?
    private var storedValidateCallCount = 0
    private var storedRemoveError: IOSPendingRecordingAudioFileSystemError?
    private var storedPublishBarrier: PendingStorePublishBarrier?
    private var storedReadBarrier: PendingLeaseReadBarrier?
    private var storedLeaseReadError: IOSPendingRecordingAudioFileSystemError?
    private var storedOnNextValidatedAudioAcquire:
        (@Sendable () -> Void)?
    private var storedCleanupDisposition: CleanupDisposition = .removed
    private var storedOnCleanup: (@Sendable () -> Void)?

    var published: Bool { lock.withLock { storedPublished } }
    var publishCallCount: Int { lock.withLock { storedPublishCallCount } }
    var leaseReleaseCount: Int { lock.withLock { storedLeaseReleaseCount } }
    var requireEmptyError: IOSPendingRecordingAudioFileSystemError? {
        get { lock.withLock { storedRequireEmptyError } }
        set { lock.withLock { storedRequireEmptyError = newValue } }
    }
    var validateError: IOSPendingRecordingAudioFileSystemError? {
        get { lock.withLock { storedValidateError } }
        set { lock.withLock { storedValidateError = newValue } }
    }
    var validateErrorCallNumber: Int? {
        get { lock.withLock { storedValidateErrorCallNumber } }
        set { lock.withLock { storedValidateErrorCallNumber = newValue } }
    }
    var removeError: IOSPendingRecordingAudioFileSystemError? {
        get { lock.withLock { storedRemoveError } }
        set { lock.withLock { storedRemoveError = newValue } }
    }
    var leaseReadError: IOSPendingRecordingAudioFileSystemError? {
        get { lock.withLock { storedLeaseReadError } }
        set { lock.withLock { storedLeaseReadError = newValue } }
    }
    var cleanupDisposition: CleanupDisposition {
        get { lock.withLock { storedCleanupDisposition } }
        set { lock.withLock { storedCleanupDisposition = newValue } }
    }

    func blockNextPublish(with barrier: PendingStorePublishBarrier) {
        lock.withLock { storedPublishBarrier = barrier }
    }

    func blockNextLeaseRead(with barrier: PendingLeaseReadBarrier) {
        lock.withLock { storedReadBarrier = barrier }
    }

    func onNextValidatedAudioAcquire(
        _ operation: @escaping @Sendable () -> Void
    ) {
        lock.withLock {
            storedOnNextValidatedAudioAcquire = operation
        }
    }

    func onCleanup(_ operation: @escaping @Sendable () -> Void) {
        lock.withLock { storedOnCleanup = operation }
    }

    init(events: PendingStoreEventLog) {
        self.events = events
    }

    func requireEmptyNamespace() async throws {
        events.append("audio.namespace.empty")
        if let error = lock.withLock({ storedRequireEmptyError }) {
            throw error
        }
        if lock.withLock({ storedPublished }) {
            throw IOSPendingRecordingAudioFileSystemError.namespaceNotEmpty
        }
    }

    func validateProtectedAudioNamespace(
        _ inventory: IOSProtectedAudioNamespaceInventory
    ) async throws {
        _ = inventory
        events.append("audio.inventory.validate")
    }

    func reconcileProtectedAudioCleanup(
        using authorization:
            IOSPendingRecordingProtectedAudioCleanupAuthorization
    ) async throws -> IOSPendingRecordingProtectedAudioCleanupEvidence {
        events.append("audio.cleanup")
        let values = lock.withLock {
            let operation = storedOnCleanup
            storedOnCleanup = nil
            return (storedCleanupDisposition, operation)
        }
        values.1?()
        switch values.0 {
        case .removed:
            return IOSPendingRecordingProtectedAudioCleanupEvidence(
                testingRemoved: authorization.cleanupAuthorization
            )
        case .alreadyAbsent:
            return IOSPendingRecordingProtectedAudioCleanupEvidence(
                testingAlreadyAbsent: authorization.cleanupAuthorization
            )
        }
    }

    func reconcileAcceptedOutputAudioRemoval(
        using authorization:
            IOSPendingRecordingAcceptedOutputAudioRemovalAuthorization
    ) async throws
        -> IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence {
        events.append("audio.accepted-output.remove")
        if let error = lock.withLock({ storedRemoveError }) {
            throw error
        }
        let removed = lock.withLock {
            defer { storedPublished = false }
            return storedPublished
        }
        return IOSPendingRecordingAcceptedOutputAudioAbsenceEvidence(
            testing: authorization,
            removed: removed
        )
    }

    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        events.append("audio.publish")
        let barrier = lock.withLock { () -> PendingStorePublishBarrier? in
            defer { storedPublishBarrier = nil }
            return storedPublishBarrier
        }
        barrier?.block()
        lock.withLock {
            storedPublished = true
            storedPublishCallCount += 1
        }
        let relative = IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
            for: attemptID,
            format: format
        )
        return FakePendingRecordingAudioLease(
            relativeIdentifier: relative,
            artifact: AudioRecordingArtifact(
                fileURL: URL(fileURLWithPath: "/protected/recording.m4a"),
                duration: TimeInterval(durationMilliseconds) / 1_000,
                byteCount: source.byteCount
            ),
            durationMilliseconds: durationMilliseconds,
            events: events,
            onRelease: { [weak self] in
                guard let self else {
                    return
                }
                self.lock.withLock { self.storedLeaseReleaseCount += 1 }
            }
        )
    }

    func publishProtectedCopy(
        from source: AudioRecordingArtifact,
        attemptID: UUID,
        format: IOSPendingRecordingAudioFormat,
        durationMilliseconds: Int64,
        inventory: IOSProtectedAudioNamespaceInventory
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        _ = inventory
        events.append("audio.inventory.publish")
        let barrier = lock.withLock { () -> PendingStorePublishBarrier? in
            defer { storedPublishBarrier = nil }
            return storedPublishBarrier
        }
        barrier?.block()
        lock.withLock {
            storedPublished = true
            storedPublishCallCount += 1
        }
        let relative = IOSPendingRecordingStorageLocation.relativeAudioIdentifier(
            for: attemptID,
            format: format
        )
        return FakePendingRecordingAudioLease(
            relativeIdentifier: relative,
            artifact: AudioRecordingArtifact(
                fileURL: URL(fileURLWithPath: "/protected/recording.m4a"),
                duration: TimeInterval(durationMilliseconds) / 1_000,
                byteCount: source.byteCount
            ),
            durationMilliseconds: durationMilliseconds,
            events: events,
            onRelease: { [weak self] in
                guard let self else { return }
                self.lock.withLock { self.storedLeaseReleaseCount += 1 }
            }
        )
    }

    func validatePublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) async throws -> AudioRecordingArtifact {
        events.append("audio.validate")
        let error = lock.withLock { () -> IOSPendingRecordingAudioFileSystemError? in
            storedValidateCallCount += 1
            guard storedValidateErrorCallNumber == nil
                    || storedValidateErrorCallNumber == storedValidateCallCount else {
                return nil
            }
            return storedValidateError
        }
        if let error {
            throw error
        }
        return AudioRecordingArtifact(
            fileURL: URL(fileURLWithPath: "/protected/recording.m4a"),
            duration: TimeInterval(durationMilliseconds) / 1_000,
            byteCount: byteCount
        )
    }

    func acquireValidatedPublishedAudio(
        relativeIdentifier: String,
        attemptID: UUID,
        durationMilliseconds: Int64,
        byteCount: Int64
    ) async throws -> any IOSPendingRecordingPublishedAudioLease {
        let artifact = try await validatePublishedAudio(
            relativeIdentifier: relativeIdentifier,
            attemptID: attemptID,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount
        )
        let onAcquire = lock.withLock {
            defer { storedOnNextValidatedAudioAcquire = nil }
            return storedOnNextValidatedAudioAcquire
        }
        onAcquire?()
        let readBarrier = lock.withLock { () -> PendingLeaseReadBarrier? in
            defer { storedReadBarrier = nil }
            return storedReadBarrier
        }
        let readError = lock.withLock { storedLeaseReadError }
        return FakePendingRecordingAudioLease(
            relativeIdentifier: relativeIdentifier,
            artifact: artifact,
            durationMilliseconds: durationMilliseconds,
            events: events,
            readBarrier: readBarrier,
            readError: readError,
            onRelease: { [weak self] in
                guard let self else { return }
                self.lock.withLock { self.storedLeaseReleaseCount += 1 }
            }
        )
    }

    func removePublishedAudioIfPresent(
        relativeIdentifier: String,
        attemptID: UUID,
        expectedByteCount: Int64
    ) async throws -> Bool {
        events.append("audio.remove")
        if let error = lock.withLock({ storedRemoveError }) {
            throw error
        }
        return lock.withLock {
            defer { storedPublished = false }
            return storedPublished
        }
    }
}

nonisolated private final class PendingStorePublishBarrier: @unchecked Sendable {
    private let blocked = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)

    func block() {
        blocked.signal()
        _ = releaseSignal.wait(timeout: .now() + 10)
    }

    func waitUntilBlocked() -> Bool {
        blocked.wait(timeout: .now() + 10) == .success
    }

    func release() {
        releaseSignal.signal()
    }
}

private actor PendingLeaseReadBarrier {
    private var blockingContinuation: CheckedContinuation<Void, Never>?
    private var observerContinuations: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false
    private var isBlocked = false

    func block() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            blockingContinuation = continuation
            isBlocked = true
            let observers = observerContinuations
            observerContinuations.removeAll()
            for observer in observers {
                observer.resume()
            }
        }
    }

    func waitUntilBlocked() async {
        guard !isBlocked else { return }
        await withCheckedContinuation { continuation in
            observerContinuations.append(continuation)
        }
    }

    func release() {
        isReleased = true
        blockingContinuation?.resume()
        blockingContinuation = nil
    }
}

nonisolated private final class PendingStoreGateProbe: @unchecked Sendable {
    private let enqueued = DispatchSemaphore(value: 0)

    func record(_ event: IOSPendingRecordingOperationGate.Event) {
        if case .enqueued = event {
            enqueued.signal()
        }
    }

    func waitUntilEnqueued() -> Bool {
        enqueued.wait(timeout: .now() + 10) == .success
    }
}

private actor PendingExecutionProbe {
    private var didStart = false
    private var didCancel = false
    private var startObservers: [CheckedContinuation<Void, Never>] = []
    private var cancellationObservers: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        didStart = true
        let observers = startObservers
        startObservers.removeAll()
        for observer in observers {
            observer.resume()
        }
    }

    func markCancelled() {
        didCancel = true
        let observers = cancellationObservers
        cancellationObservers.removeAll()
        for observer in observers {
            observer.resume()
        }
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startObservers.append(continuation)
        }
    }

    func waitUntilCancelled() async {
        guard !didCancel else { return }
        await withCheckedContinuation { continuation in
            cancellationObservers.append(continuation)
        }
    }
}

nonisolated private final class CapturingPendingTranscriptionExecutor:
    IOSPendingTranscriptionExecutor,
    @unchecked Sendable {
    private let lock = NSLock()
    private var storedRecording: IOSPendingRecording?
    private var storedAudio: IOSPendingTranscriptionAudio?

    var recording: IOSPendingRecording? {
        lock.withLock { storedRecording }
    }

    var audio: IOSPendingTranscriptionAudio? {
        lock.withLock { storedAudio }
    }

    func transcribe(
        recording: IOSPendingRecording,
        audio: IOSPendingTranscriptionAudio
    ) async throws -> String {
        lock.withLock {
            storedRecording = recording
            storedAudio = audio
        }
        return "transcript"
    }
}

nonisolated private final class CancellablePendingTranscriptionExecutor:
    IOSPendingTranscriptionExecutor,
    @unchecked Sendable {
    private let lock = NSLock()
    private let probe: PendingExecutionProbe
    private var storedAudio: IOSPendingTranscriptionAudio?

    var audio: IOSPendingTranscriptionAudio? {
        lock.withLock { storedAudio }
    }

    init(probe: PendingExecutionProbe) {
        self.probe = probe
    }

    func transcribe(
        recording: IOSPendingRecording,
        audio: IOSPendingTranscriptionAudio
    ) async throws -> String {
        _ = recording
        lock.withLock { storedAudio = audio }
        await probe.markStarted()
        do {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return "late transcript"
        } catch {
            await probe.markCancelled()
            throw error
        }
    }
}

nonisolated private final class ReadingPendingTranscriptionExecutor:
    IOSPendingTranscriptionExecutor,
    @unchecked Sendable {
    private let lock = NSLock()
    private let maximumByteCount: Int
    private var storedAudio: IOSPendingTranscriptionAudio?
    private var storedReadBytes: Data?

    init(maximumByteCount: Int = 8) {
        self.maximumByteCount = maximumByteCount
    }

    var audio: IOSPendingTranscriptionAudio? {
        lock.withLock { storedAudio }
    }

    var readBytes: Data? {
        lock.withLock { storedReadBytes }
    }

    func transcribe(
        recording: IOSPendingRecording,
        audio: IOSPendingTranscriptionAudio
    ) async throws -> String {
        _ = recording
        lock.withLock { storedAudio = audio }
        let bytes = try await audio.read(
            atOffset: 0,
            maximumByteCount: maximumByteCount
        )
        lock.withLock {
            storedReadBytes = bytes
        }
        return "transcript"
    }
}

private enum PendingTranscriptionExecutorTestError: Error {
    case failed
}

nonisolated private final class FailingPendingTranscriptionExecutor:
    IOSPendingTranscriptionExecutor,
    @unchecked Sendable {
    private let lock = NSLock()
    private var storedAudio: IOSPendingTranscriptionAudio?

    var audio: IOSPendingTranscriptionAudio? {
        lock.withLock { storedAudio }
    }

    func transcribe(
        recording: IOSPendingRecording,
        audio: IOSPendingTranscriptionAudio
    ) async throws -> String {
        _ = recording
        lock.withLock { storedAudio = audio }
        throw PendingTranscriptionExecutorTestError.failed
    }
}

nonisolated private final class NoncooperativePendingTranscriptionExecutor:
    IOSPendingTranscriptionExecutor,
    @unchecked Sendable {
    private enum ReleaseState {
        case waiting
        case suspended(CheckedContinuation<Void, Never>)
        case released
    }

    private let lock = NSLock()
    private let started = DispatchSemaphore(value: 0)
    private var releaseState = ReleaseState.waiting

    func transcribe(
        recording: IOSPendingRecording,
        audio: IOSPendingTranscriptionAudio
    ) async throws -> String {
        _ = recording
        _ = audio
        started.signal()
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                switch releaseState {
                case .waiting:
                    releaseState = .suspended(continuation)
                    return false
                case .suspended:
                    preconditionFailure("Executor has one invocation")
                case .released:
                    return true
                }
            }
            if shouldResume {
                continuation.resume()
            }
        }
        return "late transcript"
    }

    func waitUntilStarted() -> Bool {
        started.wait(timeout: .now() + 10) == .success
    }

    func release() {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            switch releaseState {
            case .waiting:
                releaseState = .released
                return nil
            case .suspended(let continuation):
                releaseState = .released
                return continuation
            case .released:
                return nil
            }
        }
        continuation?.resume()
    }
}

private final class FakePendingRecordingAudioLease:
    IOSPendingRecordingPublishedAudioLease,
    @unchecked Sendable {
    let relativeIdentifier: String
    let audioArtifact: AudioRecordingArtifact
    let durationMilliseconds: Int64

    private let events: PendingStoreEventLog
    private let readBarrier: PendingLeaseReadBarrier?
    private let readError: IOSPendingRecordingAudioFileSystemError?
    private let onRelease: @Sendable () -> Void

    init(
        relativeIdentifier: String,
        artifact: AudioRecordingArtifact,
        durationMilliseconds: Int64,
        events: PendingStoreEventLog,
        readBarrier: PendingLeaseReadBarrier? = nil,
        readError: IOSPendingRecordingAudioFileSystemError? = nil,
        onRelease: @escaping @Sendable () -> Void
    ) {
        self.relativeIdentifier = relativeIdentifier
        audioArtifact = artifact
        self.durationMilliseconds = durationMilliseconds
        self.events = events
        self.readBarrier = readBarrier
        self.readError = readError
        self.onRelease = onRelease
    }

    func revalidate() async throws -> AudioRecordingArtifact {
        events.append("audio.lease.revalidate")
        return audioArtifact
    }

    func read(
        atOffset offset: Int64,
        maximumByteCount: Int
    ) async throws -> Data {
        events.append("audio.lease.read")
        if let readError {
            throw readError
        }
        if let readBarrier {
            await readBarrier.block()
        }
        guard offset >= 0,
              offset <= audioArtifact.byteCount,
              maximumByteCount > 0 else {
            throw IOSPendingRecordingAudioFileSystemError.protectedAudioInvalid
        }
        let count = min(
            maximumByteCount,
            Int(audioArtifact.byteCount - offset)
        )
        return Data(repeating: 0x5A, count: count)
    }

    func release() {
        events.append("audio.lease.release")
        onRelease()
    }
}

private final class FakePendingDestinationInspector:
    IOSPendingRecordingDestinationInspecting,
    @unchecked Sendable {
    private let lock = NSLock()
    private var storedHasDestination = false
    private var storedError: IOSPendingRecordingError?
    private var storedInspectionCallCount = 0

    var hasDestination: Bool {
        get { lock.withLock { storedHasDestination } }
        set { lock.withLock { storedHasDestination = newValue } }
    }

    var error: IOSPendingRecordingError? {
        get { lock.withLock { storedError } }
        set { lock.withLock { storedError = newValue } }
    }

    var inspectionCallCount: Int {
        lock.withLock { storedInspectionCallCount }
    }

    func inspectCanonicalDestination(
        for recording: IOSPendingRecording,
        expectedRepositoryRoot: IOSPersistenceRepositoryRootIdentity?
    ) throws -> IOSPendingRecordingCanonicalDestinationDisposition {
        _ = recording
        _ = expectedRepositoryRoot
        let result = lock.withLock { () -> Result<Bool, IOSPendingRecordingError> in
            storedInspectionCallCount += 1
            if let storedError { return .failure(storedError) }
            return .success(storedHasDestination)
        }
        switch result {
        case .failure(let error):
            throw error
        case .success(true):
            return .exactDestination
        case .success(false):
            return .provenAbsent
        }
    }
}

private final class PendingStoreEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.withLock { storedValues }
    }

    func append(_ value: String) {
        lock.withLock { storedValues.append(value) }
    }

    func reset() {
        lock.withLock { storedValues.removeAll() }
    }
}

private final class PublicDestinationProofCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedAttemptID: UUID?
    private var storedTranscriptionID: UUID?

    var attemptID: UUID? { lock.withLock { storedAttemptID } }
    var transcriptionID: UUID? { lock.withLock { storedTranscriptionID } }

    func record(attemptID: UUID, transcriptionID: UUID) {
        lock.withLock {
            storedAttemptID = attemptID
            storedTranscriptionID = transcriptionID
        }
    }
}
