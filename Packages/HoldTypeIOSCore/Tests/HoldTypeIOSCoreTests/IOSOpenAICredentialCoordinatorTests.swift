import Foundation
import HoldTypeOpenAI
import HoldTypePersistence
import Testing
@testable import HoldTypeIOSCore

nonisolated private let fixtureDate = Date(timeIntervalSince1970: 1_789_000_000)

struct IOSOpenAICredentialCoordinatorTests {
    @Test func constructionAndEveryPassiveMarkerStatusPerformNoKeychainWork() async throws {
        let fixtures: [(CredentialPresenceMarker?, IOSOpenAICredentialPrimaryStatus, Bool)] = [
            (try marker(.present), .savedLastKnown, false),
            (try marker(.absent), .notConfigured, false),
            (try marker(.unknown), .notCheckedInThisProcess, true),
            (
                try marker(.mutationInProgress, mutationKind: .saveOrReplace),
                .notCheckedInThisProcess,
                true
            ),
            (nil, .notCheckedInThisProcess, false),
        ]

        for (storedMarker, expectedPrimary, expectedRefresh) in fixtures {
            let recorder = CredentialEventRecorder()
            let keychain = ScriptedAPIKeyStore(recorder: recorder)
            let markerStore = ScriptedMarkerStore(
                marker: storedMarker,
                recorder: recorder
            )
            let coordinator = makeCoordinator(
                keychain: keychain,
                markerStore: markerStore
            )

            #expect(await keychain.calls.isEmpty)
            let status = await coordinator.credentialStatusUpdate().status

            #expect(status.primary == expectedPrimary)
            #expect(status.statusNeedsRefresh == expectedRefresh)
            #expect(status.localMarkerIssue == nil)
            #expect(await keychain.calls.isEmpty)
            #expect(recorder.events == [.markerLoad])
        }
    }

    @Test func unreadablePassiveMarkerIsPreservedAndDoesNotReadKeychain() async {
        let recorder = CredentialEventRecorder()
        let keychain = ScriptedAPIKeyStore(storedKey: "sk-never-read", recorder: recorder)
        let markerStore = ScriptedMarkerStore(
            marker: nil,
            loadFails: true,
            recorder: recorder
        )
        let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)

        let status = await coordinator.credentialStatusUpdate().status

        #expect(status.primary == .notCheckedInThisProcess)
        #expect(status.statusNeedsRefresh == false)
        #expect(status.localMarkerIssue == .unavailable)
        #expect(await keychain.calls.isEmpty)
        #expect(markerStore.saveCallCount == 0)
        #expect(markerStore.removeCallCount == 0)
    }

    @Test func saveOrdersMarkerKeychainCacheTruthAndFinalMarker() async throws {
        let recorder = CredentialEventRecorder()
        let keychain = ScriptedAPIKeyStore(recorder: recorder)
        let markerStore = ScriptedMarkerStore(marker: nil, recorder: recorder)
        let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)

        let outcome = try await coordinator.saveOrReplace("  sk-new\n")

        #expect(outcome == .applied)
        #expect(await keychain.storedKey == "sk-new")
        #expect(markerStore.marker?.state == .present)
        #expect(recorder.events == [
            .markerLoad,
            .markerSave(.mutationInProgress, .saveOrReplace),
            .keychainSave,
            .markerSave(.present, nil),
        ])

        let resolution = try await coordinator.resolve(for: .voicePreflight)
        #expect(try resolvedKey(in: resolution) == "sk-new")
        #expect(await keychain.calls == [.save])
    }

    @Test func emptySaveStopsBeforeMarkerOrKeychain() async {
        let recorder = CredentialEventRecorder()
        let keychain = ScriptedAPIKeyStore(recorder: recorder)
        let markerStore = ScriptedMarkerStore(marker: nil, recorder: recorder)
        let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)

        await expectCoordinatorError(.emptyAPIKey) {
            _ = try await coordinator.saveOrReplace(" \n\t ")
        }

        #expect(recorder.events.isEmpty)
        #expect(await keychain.calls.isEmpty)
    }

    @Test func unreadableOrFailedPremutationMarkerBlocksSaveAndRemove() async {
        for operation in [CredentialMutationKindForTest.save, .remove] {
            let recorder = CredentialEventRecorder()
            let keychain = ScriptedAPIKeyStore(storedKey: "sk-old", recorder: recorder)
            let markerStore = ScriptedMarkerStore(
                marker: try? marker(.present),
                loadFails: true,
                recorder: recorder
            )
            let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)

            await expectCoordinatorError(.markerUnavailable) {
                switch operation {
                case .save:
                    _ = try await coordinator.saveOrReplace("sk-new")
                case .remove:
                    _ = try await coordinator.remove()
                }
            }

            #expect(await keychain.calls.isEmpty)
            #expect(markerStore.saveCallCount == 0)
        }

        let recorder = CredentialEventRecorder()
        let keychain = ScriptedAPIKeyStore(recorder: recorder)
        let markerStore = ScriptedMarkerStore(
            marker: nil,
            saveResults: [.failure],
            recorder: recorder
        )
        let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)

        await expectCoordinatorError(.markerUnavailable) {
            _ = try await coordinator.saveOrReplace("sk-new")
        }
        #expect(await keychain.calls.isEmpty)
    }

    @Test func failedSaveRestoresExactPriorMarkerAndRuntimeCredential() async throws {
        let recorder = CredentialEventRecorder()
        let keychain = ScriptedAPIKeyStore(storedKey: "sk-old", recorder: recorder)
        let priorMarker = try marker(.present)
        let markerStore = ScriptedMarkerStore(marker: priorMarker, recorder: recorder)
        let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)
        _ = try await coordinator.resolve(for: .openAISettingsRefresh)
        await keychain.setSaveError(.keychainFailure)
        recorder.removeAll()

        await expectCoordinatorError(
            .credentialAccessFailed(.keychainFailure, markerRestorationFailed: false)
        ) {
            _ = try await coordinator.saveOrReplace("sk-new")
        }

        #expect(await keychain.storedKey == "sk-old")
        #expect(markerStore.marker == priorMarker)
        #expect(recorder.events == [
            .markerLoad,
            .markerSave(.mutationInProgress, .saveOrReplace),
            .keychainSave,
            .markerSave(.present, nil),
        ])
        let cachedOld = try await coordinator.resolve(for: .voicePreflight)
        #expect(try resolvedKey(in: cachedOld) == "sk-old")
    }

    @Test func failedSaveRestoresAnExactlyMissingMarker() async {
        let recorder = CredentialEventRecorder()
        let keychain = ScriptedAPIKeyStore(
            saveError: .keychainFailure,
            recorder: recorder
        )
        let markerStore = ScriptedMarkerStore(marker: nil, recorder: recorder)
        let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)

        await expectCoordinatorError(
            .credentialAccessFailed(.keychainFailure, markerRestorationFailed: false)
        ) {
            _ = try await coordinator.saveOrReplace("sk-new")
        }

        #expect(markerStore.marker == nil)
        #expect(markerStore.removeCallCount == 1)
        #expect(recorder.events == [
            .markerLoad,
            .markerSave(.mutationInProgress, .saveOrReplace),
            .keychainSave,
            .markerRemove,
        ])
    }

    @Test func failedExactRestoreFallsBackToUnknownWithoutChangingCache() async throws {
        let recorder = CredentialEventRecorder()
        let keychain = ScriptedAPIKeyStore(
            storedKey: "sk-old",
            saveError: .unavailableWhileLocked,
            recorder: recorder
        )
        let markerStore = ScriptedMarkerStore(
            marker: nil,
            removeResults: [.failure],
            recorder: recorder
        )
        let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)

        await expectCoordinatorError(
            .credentialAccessFailed(
                .unavailableWhileLocked,
                markerRestorationFailed: true
            )
        ) {
            _ = try await coordinator.saveOrReplace("sk-new")
        }

        #expect(await keychain.storedKey == "sk-old")
        #expect(markerStore.marker?.state == .unknown)
        let status = await coordinator.credentialStatusUpdate().status
        #expect(status.primary == .notCheckedInThisProcess)
        #expect(status.statusNeedsRefresh)
    }

    @Test func finalSaveMarkerFailureIsPartialSuccessAndNeverRollsBack() async throws {
        let recorder = CredentialEventRecorder()
        let keychain = ScriptedAPIKeyStore(recorder: recorder)
        let markerStore = ScriptedMarkerStore(
            marker: nil,
            saveResults: [.success, .failure],
            recorder: recorder
        )
        let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)

        let outcome = try await coordinator.saveOrReplace("sk-new")

        #expect(outcome == .appliedStatusNeedsRefresh)
        #expect(await keychain.storedKey == "sk-new")
        #expect(await keychain.calls == [.save])
        #expect(markerStore.marker?.state == .mutationInProgress)
        let status = await coordinator.credentialStatusUpdate().status
        #expect(status.primary == .availableInThisProcess)
        #expect(status.statusNeedsRefresh)
    }

    @Test func freshProcessRepairsInterruptedSaveWithoutPassiveKeychainRead() async throws {
        let keychain = ScriptedAPIKeyStore()
        let markerStore = ScriptedMarkerStore(
            marker: nil,
            saveResults: [.success, .failure]
        )
        let firstProcess = makeCoordinator(keychain: keychain, markerStore: markerStore)

        #expect(
            try await firstProcess.saveOrReplace("sk-new")
                == .appliedStatusNeedsRefresh
        )
        #expect(markerStore.marker?.state == .mutationInProgress)
        #expect(await keychain.calls == [.save])

        let freshProcess = makeCoordinator(keychain: keychain, markerStore: markerStore)
        let passiveStatus = await freshProcess.credentialStatusUpdate().status
        #expect(passiveStatus.primary == .notCheckedInThisProcess)
        #expect(passiveStatus.statusNeedsRefresh)
        #expect(await keychain.calls == [.save])

        let resolved = try await freshProcess.resolve(for: .voicePreflight)
        #expect(try resolvedKey(in: resolved) == "sk-new")
        #expect(await keychain.calls == [.save, .load])
        #expect(markerStore.marker?.state == .present)
        #expect(resolved.status.primary == .availableInThisProcess)
        #expect(resolved.status.statusNeedsRefresh == false)
    }

    @Test func removeMirrorsSuccessFailureAndPartialSuccessSemantics() async throws {
        let successKeychain = ScriptedAPIKeyStore(storedKey: "sk-old")
        let successMarker = ScriptedMarkerStore(marker: try marker(.present))
        let successCoordinator = makeCoordinator(
            keychain: successKeychain,
            markerStore: successMarker
        )
        _ = try await successCoordinator.resolve(for: .openAISettingsRefresh)

        #expect(try await successCoordinator.remove() == .applied)
        #expect(await successKeychain.storedKey == nil)
        #expect(successMarker.marker?.state == .absent)
        let absentResolution = try await successCoordinator.resolve(for: .voicePreflight)
        #expect(absentResolution.resolution == .notConfigured)
        #expect(absentResolution.status.primary == .notConfigured)
        #expect(absentResolution.status.statusNeedsRefresh == false)
        #expect(await successKeychain.calls.filter { $0 == .load }.count == 1)

        let failedKeychain = ScriptedAPIKeyStore(
            storedKey: "sk-old",
            removeError: .unavailableWhileLocked
        )
        let priorMarker = try marker(.present)
        let failedMarker = ScriptedMarkerStore(marker: priorMarker)
        let failedCoordinator = makeCoordinator(
            keychain: failedKeychain,
            markerStore: failedMarker
        )

        await expectCoordinatorError(
            .credentialAccessFailed(
                .unavailableWhileLocked,
                markerRestorationFailed: false
            )
        ) {
            _ = try await failedCoordinator.remove()
        }
        #expect(await failedKeychain.storedKey == "sk-old")
        #expect(failedMarker.marker == priorMarker)

        let partialKeychain = ScriptedAPIKeyStore(storedKey: "sk-old")
        let partialMarker = ScriptedMarkerStore(
            marker: priorMarker,
            saveResults: [.success, .failure]
        )
        let partialCoordinator = makeCoordinator(
            keychain: partialKeychain,
            markerStore: partialMarker
        )

        #expect(try await partialCoordinator.remove() == .appliedStatusNeedsRefresh)
        #expect(await partialKeychain.storedKey == nil)
        #expect(partialMarker.marker?.state == .mutationInProgress)
        let partialStatus = await partialCoordinator.credentialStatusUpdate().status
        #expect(partialStatus.primary == .notConfigured)
        #expect(partialStatus.statusNeedsRefresh)
    }

    @Test func freshProcessRepairsInterruptedRemoveWithoutPassiveKeychainRead() async throws {
        let keychain = ScriptedAPIKeyStore(storedKey: "sk-old")
        let markerStore = ScriptedMarkerStore(
            marker: try marker(.present),
            saveResults: [.success, .failure]
        )
        let firstProcess = makeCoordinator(keychain: keychain, markerStore: markerStore)

        #expect(try await firstProcess.remove() == .appliedStatusNeedsRefresh)
        #expect(markerStore.marker?.state == .mutationInProgress)
        #expect(await keychain.calls == [.remove])

        let freshProcess = makeCoordinator(keychain: keychain, markerStore: markerStore)
        let passiveStatus = await freshProcess.credentialStatusUpdate().status
        #expect(passiveStatus.primary == .notCheckedInThisProcess)
        #expect(passiveStatus.statusNeedsRefresh)
        #expect(await keychain.calls == [.remove])

        let resolved = try await freshProcess.resolve(for: .openAISettingsRefresh)
        #expect(resolved.resolution == .notConfigured)
        #expect(await keychain.calls == [.remove, .load])
        #expect(markerStore.marker?.state == .absent)
        #expect(resolved.status.primary == .notConfigured)
        #expect(resolved.status.statusNeedsRefresh == false)
    }

    @Test func explicitResolveReconcilesUnknownAndContradictoryMarkers() async throws {
        let unknownMarker = ScriptedMarkerStore(
            marker: try marker(.mutationInProgress, mutationKind: .remove)
        )
        let presentKeychain = ScriptedAPIKeyStore(storedKey: "sk-present")
        let unknownCoordinator = makeCoordinator(
            keychain: presentKeychain,
            markerStore: unknownMarker
        )

        let presentOutcome = try await unknownCoordinator.resolve(
            for: .openAISettingsRefresh
        )
        #expect(try resolvedKey(in: presentOutcome) == "sk-present")
        #expect(unknownMarker.savedStates == [.present])

        let contradictoryMarker = ScriptedMarkerStore(marker: try marker(.present))
        let absentKeychain = ScriptedAPIKeyStore(storedKey: nil)
        let contradictoryCoordinator = makeCoordinator(
            keychain: absentKeychain,
            markerStore: contradictoryMarker
        )

        let absentOutcome = try await contradictoryCoordinator.resolve(
            for: .openAISettingsRefresh
        )
        #expect(absentOutcome.resolution == .notConfigured)
        #expect(contradictoryMarker.savedStates == [.unknown, .absent])
    }

    @Test func explicitResolveAttemptsFinalTruthEvenWhenUnknownPreparationFails() async throws {
        let markerStore = ScriptedMarkerStore(
            marker: nil,
            saveResults: [.failure, .success]
        )
        let coordinator = makeCoordinator(
            keychain: ScriptedAPIKeyStore(storedKey: "sk-present"),
            markerStore: markerStore
        )

        let outcome = try await coordinator.resolve(for: .openAISettingsRefresh)

        #expect(try resolvedKey(in: outcome) == "sk-present")
        #expect(outcome.localMarkerIssue == nil)
        #expect(markerStore.marker?.state == .present)
        #expect(markerStore.attemptedSaveStates == [.unknown, .present])
    }

    @Test func unreadableMarkerDoesNotBlockExplicitTruthOrGetOverwritten() async throws {
        let markerStore = ScriptedMarkerStore(marker: nil, loadFails: true)
        let keychain = ScriptedAPIKeyStore(storedKey: "sk-present")
        let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)

        let outcome = try await coordinator.resolve(for: .voicePreflight)

        #expect(try resolvedKey(in: outcome) == "sk-present")
        #expect(outcome.localMarkerIssue == .unavailable)
        #expect(markerStore.saveCallCount == 0)
        #expect(markerStore.removeCallCount == 0)
        let status = await coordinator.credentialStatusUpdate().status
        #expect(status.primary == .availableInThisProcess)
        #expect(status.localMarkerIssue == .unavailable)
    }

    @Test func failedResolutionFinalizationKeepsResolvedTruthAndReportsIssue() async throws {
        let markerStore = ScriptedMarkerStore(
            marker: try marker(.absent),
            saveResults: [.success, .failure]
        )
        let coordinator = makeCoordinator(
            keychain: ScriptedAPIKeyStore(storedKey: "sk-present"),
            markerStore: markerStore
        )

        let outcome = try await coordinator.resolve(for: .openAISettingsRefresh)

        #expect(try resolvedKey(in: outcome) == "sk-present")
        #expect(outcome.localMarkerIssue == .unavailable)
        #expect(markerStore.marker?.state == .unknown)
        let cached = try await coordinator.resolve(for: .voicePreflight)
        #expect(try resolvedKey(in: cached) == "sk-present")
    }

    @Test func exactResolutionIssueReachesOutcomeAndStatusStream()
        async throws {
        let markerStore = ScriptedMarkerStore(
            marker: try marker(.absent),
            saveResults: [.failure, .failure]
        )
        let coordinator = makeCoordinator(
            keychain: ScriptedAPIKeyStore(storedKey: "sk-present"),
            markerStore: markerStore
        )
        let updates = await coordinator.statusUpdates()
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()

        let outcome = try await coordinator.resolve(
            for: .openAISettingsRefresh
        )
        let streamedUpdate = await iterator.next()

        #expect(try resolvedKey(in: outcome) == "sk-present")
        #expect(outcome.localMarkerIssue == .unavailable)
        #expect(streamedUpdate == outcome.statusUpdate)
        #expect(streamedUpdate?.status.localMarkerIssue == .unavailable)
        #expect(markerStore.marker?.state == .absent)
        #expect(
            (await coordinator.credentialStatusUpdate().status).localMarkerIssue
                == .unavailable
        )

        let recovered = try await coordinator.resolve(
            for: .voicePreflight
        )
        #expect(recovered.localMarkerIssue == nil)
        #expect(markerStore.marker?.state == .present)
        #expect(
            (await coordinator.credentialStatusUpdate().status).localMarkerIssue == nil
        )
    }

    @Test func rejectedCachePreservesFailedReconciliationInStream()
        async throws {
        let markerStore = ScriptedMarkerStore(
            marker: try marker(.absent),
            saveResults: [
                .failure, .failure,
                .failure, .failure,
            ]
        )
        let coordinator = makeCoordinator(
            keychain: ScriptedAPIKeyStore(storedKey: "sk-present"),
            markerStore: markerStore
        )
        let updates = await coordinator.statusUpdates()
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()

        let resolved = try await coordinator.resolve(
            for: .openAISettingsRefresh
        )
        _ = await iterator.next()
        let generation = try #require(
            availableHandle(in: resolved)
        ).generation
        await coordinator.recordProviderRejection(for: generation)
        _ = await iterator.next()

        await expectCoordinatorError(.providerRejected) {
            _ = try await coordinator.resolve(for: .voicePreflight)
        }
        let rejectedUpdate = await iterator.next()

        #expect(rejectedUpdate?.status.primary == .providerRejected)
        #expect(
            rejectedUpdate?.status.localMarkerIssue == .unavailable
        )
        #expect(markerStore.marker?.state == .absent)
    }

    @Test func freshLockedResolutionRetriesAndDoesNotClearAnExistingCredential() async throws {
        let keychain = ScriptedAPIKeyStore(
            storedKey: "sk-present",
            loadError: .unavailableWhileLocked
        )
        let coordinator = makeCoordinator(
            keychain: keychain,
            markerStore: ScriptedMarkerStore(marker: try marker(.present))
        )

        await expectCoordinatorError(
            .credentialAccessFailed(
                .unavailableWhileLocked,
                markerRestorationFailed: false
            )
        ) {
            _ = try await coordinator.resolve(for: .voicePreflight)
        }
        #expect(
            (await coordinator.credentialStatusUpdate().status).primary
                == .unavailableWhileLocked
        )

        await keychain.setLoadError(nil)
        let recovered = try await coordinator.resolve(for: .voicePreflight)
        #expect(try resolvedKey(in: recovered) == "sk-present")

        await keychain.setLoadError(.unavailableWhileLocked)
        await expectCoordinatorError(
            .credentialAccessFailed(
                .unavailableWhileLocked,
                markerRestorationFailed: false
            )
        ) {
            _ = try await coordinator.resolve(for: .openAISettingsRefresh)
        }
        await keychain.setLoadError(nil)
        let cached = try await coordinator.resolve(for: .voicePreflight)
        #expect(try resolvedKey(in: cached) == "sk-present")
    }

    @Test func genericFailureAfterLockedResolutionClearsTheLockedStatus() async throws {
        let keychain = ScriptedAPIKeyStore(
            storedKey: "sk-present",
            loadError: .unavailableWhileLocked
        )
        let coordinator = makeCoordinator(
            keychain: keychain,
            markerStore: ScriptedMarkerStore(marker: try marker(.present))
        )

        await expectCredentialAccessFailure(.unavailableWhileLocked) {
            _ = try await coordinator.resolve(for: .voicePreflight)
        }
        #expect(
            (await coordinator.credentialStatusUpdate().status).primary
                == .unavailableWhileLocked
        )

        await keychain.setLoadError(.keychainFailure)
        await expectCredentialAccessFailure(.keychainFailure) {
            _ = try await coordinator.resolve(for: .voicePreflight)
        }

        #expect((await coordinator.credentialStatusUpdate().status).primary == .savedLastKnown)
    }

    @Test func invalidStoredValueAfterLockedResolutionClearsTheLockedStatus() async throws {
        let fixtures: [(
            storedKey: String?,
            nextLoadError: OpenAIAPIKeyKeychainStorageError?
        )] = [
            (nil, .invalidStoredAPIKey),
            (" \n\t ", nil),
        ]

        for fixture in fixtures {
            let keychain = ScriptedAPIKeyStore(
                storedKey: fixture.storedKey,
                loadError: .unavailableWhileLocked
            )
            let coordinator = makeCoordinator(
                keychain: keychain,
                markerStore: ScriptedMarkerStore(marker: try marker(.present))
            )

            await expectCredentialAccessFailure(.unavailableWhileLocked) {
                _ = try await coordinator.resolve(for: .voicePreflight)
            }
            await keychain.setLoadError(fixture.nextLoadError)
            await expectCredentialAccessFailure(.invalidStoredCredential) {
                _ = try await coordinator.resolve(for: .voicePreflight)
            }

            #expect((await coordinator.credentialStatusUpdate().status).primary == .savedLastKnown)
        }
    }

    @Test func absenceAfterLockedResolutionClearsTheLockedStatus() async throws {
        let keychain = ScriptedAPIKeyStore(
            storedKey: nil,
            loadError: .unavailableWhileLocked
        )
        let markerStore = ScriptedMarkerStore(marker: try marker(.present))
        let coordinator = makeCoordinator(
            keychain: keychain,
            markerStore: markerStore
        )

        await expectCredentialAccessFailure(.unavailableWhileLocked) {
            _ = try await coordinator.resolve(for: .voicePreflight)
        }
        await keychain.setLoadError(nil)
        let resolved = try await coordinator.resolve(for: .voicePreflight)

        #expect(resolved.resolution == .notConfigured)
        #expect(resolved.status.primary == .notConfigured)
        #expect((await coordinator.credentialStatusUpdate().status).primary == .notConfigured)
        #expect(markerStore.marker?.state == .absent)
    }

    @Test func voiceIsCacheFirstForKnownAbsenceWhileSettingsForcesKeychain() async throws {
        let keychain = ScriptedAPIKeyStore(storedKey: nil)
        let coordinator = makeCoordinator(
            keychain: keychain,
            markerStore: ScriptedMarkerStore(marker: try marker(.absent))
        )

        _ = try await coordinator.resolve(for: .openAISettingsRefresh)
        _ = try await coordinator.resolve(for: .voicePreflight)
        #expect(await keychain.calls == [.load])

        _ = try await coordinator.resolve(for: .openAISettingsRefresh)
        #expect(await keychain.calls == [.load, .load])
    }

    @Test func providerRejectionIsGenerationBoundAndBlocksOnlyCurrentVoiceCache() async throws {
        let keychain = ScriptedAPIKeyStore()
        let coordinator = makeCoordinator(
            keychain: keychain,
            markerStore: ScriptedMarkerStore(marker: nil)
        )

        _ = try await coordinator.saveOrReplace("sk-first")
        let firstResolution = try await coordinator.resolve(for: .voicePreflight)
        let first = try #require(availableHandle(in: firstResolution))
        await coordinator.recordProviderRejection(for: first.generation)
        #expect((await coordinator.credentialStatusUpdate().status).primary == .providerRejected)
        await expectCoordinatorError(.providerRejected) {
            _ = try await coordinator.resolve(for: .voicePreflight)
        }

        _ = try await coordinator.saveOrReplace("sk-second")
        await coordinator.recordProviderRejection(for: first.generation)
        #expect(
            (await coordinator.credentialStatusUpdate().status).primary
                == .availableInThisProcess
        )
        let second = try await coordinator.resolve(for: .voicePreflight)
        #expect(try resolvedKey(in: second) == "sk-second")
        #expect(await keychain.calls.filter { $0 == .load }.isEmpty)
    }

    @Test func suspendedSaveAndRemoveNeverInterleave() async throws {
        let recorder = CredentialEventRecorder()
        let gateProbe = CredentialGateEventProbe()
        let operationGate = CredentialOperationGate { event in
            gateProbe.record(event)
        }
        let saveGate = AsyncCallGate()
        let keychain = ScriptedAPIKeyStore(
            storedKey: nil,
            saveGate: saveGate,
            recorder: recorder
        )
        let markerStore = ScriptedMarkerStore(marker: nil, recorder: recorder)
        let coordinator = makeCoordinator(
            keychain: keychain,
            markerStore: markerStore,
            operationGate: operationGate
        )

        let saveTask = Task { try await coordinator.saveOrReplace("sk-new") }
        await saveGate.waitUntilEntered()
        let removeTask = Task { try await coordinator.remove() }
        await gateProbe.waitForEnqueuedCount(1)

        #expect(recorder.events == [
            .markerLoad,
            .markerSave(.mutationInProgress, .saveOrReplace),
            .keychainSave,
        ])

        await saveGate.open()
        #expect(try await saveTask.value == .applied)
        #expect(try await removeTask.value == .applied)
        #expect(recorder.events == [
            .markerLoad,
            .markerSave(.mutationInProgress, .saveOrReplace),
            .keychainSave,
            .markerSave(.present, nil),
            .markerLoad,
            .markerSave(.mutationInProgress, .remove),
            .keychainRemove,
            .markerSave(.absent, nil),
        ])
    }

    @Test func resolveWaitsForACompleteSuspendedMutation() async throws {
        let recorder = CredentialEventRecorder()
        let gateProbe = CredentialGateEventProbe()
        let operationGate = CredentialOperationGate { event in
            gateProbe.record(event)
        }
        let saveGate = AsyncCallGate()
        let keychain = ScriptedAPIKeyStore(saveGate: saveGate, recorder: recorder)
        let markerStore = ScriptedMarkerStore(marker: nil, recorder: recorder)
        let coordinator = makeCoordinator(
            keychain: keychain,
            markerStore: markerStore,
            operationGate: operationGate
        )

        let saveTask = Task { try await coordinator.saveOrReplace("sk-new") }
        await saveGate.waitUntilEntered()
        let resolveTask = Task {
            try await coordinator.resolve(for: .openAISettingsRefresh)
        }
        await gateProbe.waitForEnqueuedCount(1)

        #expect(await keychain.calls == [.save])
        await saveGate.open()
        _ = try await saveTask.value
        let resolution = try await resolveTask.value

        #expect(try resolvedKey(in: resolution) == "sk-new")
        #expect(await keychain.calls == [.save, .load])
        #expect(markerStore.marker?.state == .present)
    }

    @Test func cancellationBeforeLeaseDoesNoWork() async throws {
        let recorder = CredentialEventRecorder()
        let gateProbe = CredentialGateEventProbe()
        let operationGate = CredentialOperationGate { event in
            gateProbe.record(event)
        }
        let saveGate = AsyncCallGate()
        let keychain = ScriptedAPIKeyStore(saveGate: saveGate, recorder: recorder)
        let markerStore = ScriptedMarkerStore(marker: nil, recorder: recorder)
        let coordinator = makeCoordinator(
            keychain: keychain,
            markerStore: markerStore,
            operationGate: operationGate
        )

        let saveTask = Task { try await coordinator.saveOrReplace("sk-new") }
        await saveGate.waitUntilEntered()
        let removeTask = Task { try await coordinator.remove() }
        await gateProbe.waitForEnqueuedCount(1)
        removeTask.cancel()

        await expectTaskError(
            .operationCancelledBeforeStart,
            from: removeTask
        )

        #expect(recorder.events == [
            .markerLoad,
            .markerSave(.mutationInProgress, .saveOrReplace),
            .keychainSave,
        ])
        await saveGate.open()
        _ = try await saveTask.value
        #expect(await keychain.calls == [.save])
    }

    @Test func cancellationAfterPremutationMarkerStillFinalizesTheTransaction() async throws {
        let saveGate = AsyncCallGate()
        let keychain = ScriptedAPIKeyStore(saveGate: saveGate)
        let markerStore = ScriptedMarkerStore(marker: nil)
        let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)

        let task = Task { try await coordinator.saveOrReplace("sk-new") }
        await saveGate.waitUntilEntered()
        task.cancel()
        await saveGate.open()

        #expect(try await task.value == .applied)
        #expect(await keychain.storedKey == "sk-new")
        #expect(markerStore.marker?.state == .present)
    }

    @Test func cancellationAtTheGrantLinearizationPointStillRunsTheShieldedTransaction() async throws {
        let gateProbe = CredentialGateEventProbe()
        let cancellationBox = TaskCancellationBox()
        let operationGate = CredentialOperationGate { event in
            gateProbe.record(event)
        }
        let saveGate = AsyncCallGate()
        let keychain = ScriptedAPIKeyStore(saveGate: saveGate)
        let markerStore = ScriptedMarkerStore(marker: nil)
        let coordinator = makeCoordinator(
            keychain: keychain,
            markerStore: markerStore,
            operationGate: operationGate
        )

        let firstTask = Task { try await coordinator.saveOrReplace("sk-first") }
        await saveGate.waitUntilEntered()
        let secondTask = Task { try await coordinator.remove() }
        cancellationBox.install { secondTask.cancel() }
        await gateProbe.waitForEnqueuedCount(1)
        gateProbe.runOnNextGrant { cancellationBox.cancel() }

        await saveGate.open()
        #expect(try await firstTask.value == .applied)
        #expect(try await secondTask.value == .applied)
        #expect(await keychain.calls == [.save, .remove])
        #expect(markerStore.marker?.state == .absent)
    }

    @Test func cancellationAwareKeychainFailureRestoresBeforeReportingCancellation() async {
        let keychain = ScriptedAPIKeyStore(saveIsCancelled: true)
        let priorMarker = try? marker(.present)
        let markerStore = ScriptedMarkerStore(marker: priorMarker)
        let coordinator = makeCoordinator(keychain: keychain, markerStore: markerStore)

        do {
            _ = try await coordinator.saveOrReplace("sk-new")
            Issue.record("Expected operation cancellation")
        } catch is CancellationError {
            // Exact restoration completed before cancellation escaped.
        } catch {
            Issue.record("Unexpected cancellation error")
        }

        #expect(markerStore.marker == priorMarker)
        #expect(await keychain.storedKey == nil)
    }

    @Test func publicDiagnosticsStayRedacted() async throws {
        let sentinel = "sk-never-render-this"
        let coordinator = makeCoordinator(
            keychain: ScriptedAPIKeyStore(),
            markerStore: ScriptedMarkerStore(marker: nil)
        )
        _ = try await coordinator.saveOrReplace(sentinel)
        let outcome = try await coordinator.resolve(for: .voicePreflight)
        let handle = try #require(availableHandle(in: outcome))
        let status = await coordinator.credentialStatusUpdate().status
        let statusUpdate = await coordinator.credentialStatusUpdate()
        let values: [Any] = [
            coordinator,
            status,
            statusUpdate,
            IOSOpenAICredentialMutationOutcome.applied,
            outcome,
            outcome.resolution,
            handle,
            handle.generation,
            IOSOpenAICredentialLocalMarkerIssue.unavailable,
            IOSOpenAICredentialCoordinatorError.credentialAccessFailed(
                .keychainFailure,
                markerRestorationFailed: true
            ),
        ]

        for value in values {
            var dumped = ""
            dump(value, to: &dumped)
            let renderings = [
                String(describing: value),
                String(reflecting: value),
                dumped,
            ]
            for rendering in renderings {
                #expect(!rendering.contains(sentinel))
                #expect(!rendering.contains("-25308"))
                #expect(!rendering.contains("-34018"))
            }
        }
    }

    @Test func statusUpdatesArePayloadFreeAndTrackExternalTruth()
        async throws {
        let coordinator = makeCoordinator(
            keychain: ScriptedAPIKeyStore(),
            markerStore: ScriptedMarkerStore(marker: nil)
        )
        let updates = await coordinator.statusUpdates()
        var iterator = updates.makeAsyncIterator()

        let initialUpdate = await iterator.next()
        #expect(
            initialUpdate?.status == IOSOpenAICredentialStatus(
                primary: .notCheckedInThisProcess,
                statusNeedsRefresh: false,
                localMarkerIssue: nil
            )
        )
        #expect(initialUpdate?.revision == 0)

        _ = try await coordinator.saveOrReplace("sk-status-update")
        let savedUpdate = await iterator.next()
        #expect(savedUpdate?.status.primary == .availableInThisProcess)
        #expect(savedUpdate?.revision == 1)

        let resolution = try await coordinator.resolve(for: .voicePreflight)
        let generation = try #require(
            availableHandle(in: resolution)
        ).generation
        await coordinator.recordProviderRejection(for: generation)
        let rejectedUpdate = await iterator.next()
        #expect(rejectedUpdate?.status.primary == .providerRejected)
        #expect(rejectedUpdate?.revision == 3)
    }
}

private enum CredentialMutationKindForTest {
    case save
    case remove
}

private func makeCoordinator(
    keychain: ScriptedAPIKeyStore,
    markerStore: ScriptedMarkerStore,
    operationGate: CredentialOperationGate = CredentialOperationGate()
) -> IOSOpenAICredentialCoordinator {
    IOSOpenAICredentialCoordinator(
        keychainStorage: keychain,
        markerStore: markerStore,
        now: { fixtureDate },
        operationGate: operationGate
    )
}

private func marker(
    _ state: CredentialPresenceMarker.State,
    mutationKind: CredentialPresenceMarker.MutationKind? = nil
) throws -> CredentialPresenceMarker {
    try CredentialPresenceMarker(
        state: state,
        updatedAt: fixtureDate,
        mutationKind: mutationKind
    )
}

private func availableHandle(
    in outcome: IOSOpenAICredentialResolutionOutcome
) -> IOSResolvedOpenAICredential? {
    guard case .available(let handle) = outcome.resolution else {
        return nil
    }
    return handle
}

private func resolvedKey(
    in outcome: IOSOpenAICredentialResolutionOutcome
) throws -> String {
    try #require(availableHandle(in: outcome)).credential.apiKey
}

private func expectCoordinatorError(
    _ expected: IOSOpenAICredentialCoordinatorError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected coordinator error")
    } catch let error as IOSOpenAICredentialCoordinatorError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected coordinator error type")
    }
}

private func expectCredentialAccessFailure(
    _ expected: IOSOpenAICredentialAccessFailure,
    operation: () async throws -> Void
) async {
    await expectCoordinatorError(
        .credentialAccessFailed(
            expected,
            markerRestorationFailed: false
        ),
        operation: operation
    )
}

private func expectTaskError<Success: Sendable>(
    _ expected: IOSOpenAICredentialCoordinatorError,
    from task: Task<Success, Error>
) async {
    do {
        _ = try await task.value
        Issue.record("Expected coordinator task error")
    } catch let error as IOSOpenAICredentialCoordinatorError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected coordinator task error type")
    }
}

nonisolated private enum CredentialEvent: Equatable, Sendable {
    case markerLoad
    case markerSave(
        CredentialPresenceMarker.State,
        CredentialPresenceMarker.MutationKind?
    )
    case markerRemove
    case keychainSave
    case keychainLoad
    case keychainRemove
}

nonisolated private final class CredentialEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [CredentialEvent] = []

    var events: [CredentialEvent] {
        lock.withLock { storedEvents }
    }

    func append(_ event: CredentialEvent) {
        lock.withLock { storedEvents.append(event) }
    }

    func removeAll() {
        lock.withLock { storedEvents.removeAll() }
    }
}

nonisolated private final class CredentialGateEventProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var enqueuedCount = 0
    private var enqueuedWaiters: [(
        target: Int,
        continuation: CheckedContinuation<Void, Never>
    )] = []
    private var nextGrantAction: (@Sendable () -> Void)?

    func record(_ event: CredentialOperationGate.Event) {
        if case .granted = event {
            let action = lock.withLock { () -> (@Sendable () -> Void)? in
                let action = nextGrantAction
                nextGrantAction = nil
                return action
            }
            action?()
        }

        guard case .enqueued = event else {
            return
        }

        let continuations: [CheckedContinuation<Void, Never>] = lock.withLock {
            enqueuedCount += 1
            let ready = enqueuedWaiters.filter { $0.target <= enqueuedCount }
            enqueuedWaiters.removeAll { $0.target <= enqueuedCount }
            return ready.map(\.continuation)
        }
        for continuation in continuations {
            continuation.resume()
        }
    }

    func runOnNextGrant(_ action: @escaping @Sendable () -> Void) {
        lock.withLock {
            nextGrantAction = action
        }
    }

    func waitForEnqueuedCount(_ target: Int) async {
        let alreadyReached = lock.withLock { enqueuedCount >= target }
        guard !alreadyReached else {
            return
        }

        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard enqueuedCount < target else {
                    return true
                }
                enqueuedWaiters.append((target, continuation))
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }
}

nonisolated private final class TaskCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () -> Void)?

    func install(_ action: @escaping @Sendable () -> Void) {
        lock.withLock {
            self.action = action
        }
    }

    func cancel() {
        lock.withLock { action }?()
    }
}

nonisolated private enum ScriptedMarkerResult: Sendable {
    case success
    case failure
}

nonisolated private enum ScriptedMarkerError: Error {
    case unavailable
}

nonisolated private final class ScriptedMarkerStore:
    IOSCredentialPresenceMarkerStoring,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedMarker: CredentialPresenceMarker?
    private var storedLoadFails: Bool
    private var storedSaveResults: [ScriptedMarkerResult]
    private var storedRemoveResults: [ScriptedMarkerResult]
    private var storedAttemptedSaveStates: [CredentialPresenceMarker.State] = []
    private var storedSavedStates: [CredentialPresenceMarker.State] = []
    private var storedSaveCallCount = 0
    private var storedRemoveCallCount = 0
    private let recorder: CredentialEventRecorder?

    init(
        marker: CredentialPresenceMarker?,
        loadFails: Bool = false,
        saveResults: [ScriptedMarkerResult] = [],
        removeResults: [ScriptedMarkerResult] = [],
        recorder: CredentialEventRecorder? = nil
    ) {
        storedMarker = marker
        storedLoadFails = loadFails
        storedSaveResults = saveResults
        storedRemoveResults = removeResults
        self.recorder = recorder
    }

    var marker: CredentialPresenceMarker? {
        lock.withLock { storedMarker }
    }

    var attemptedSaveStates: [CredentialPresenceMarker.State] {
        lock.withLock { storedAttemptedSaveStates }
    }

    var savedStates: [CredentialPresenceMarker.State] {
        lock.withLock { storedSavedStates }
    }

    var saveCallCount: Int {
        lock.withLock { storedSaveCallCount }
    }

    var removeCallCount: Int {
        lock.withLock { storedRemoveCallCount }
    }

    func load() throws -> CredentialPresenceMarker? {
        recorder?.append(.markerLoad)
        return try lock.withLock {
            guard !storedLoadFails else {
                throw ScriptedMarkerError.unavailable
            }
            return storedMarker
        }
    }

    func save(_ marker: CredentialPresenceMarker) throws {
        recorder?.append(.markerSave(marker.state, marker.mutationKind))
        try lock.withLock {
            storedSaveCallCount += 1
            storedAttemptedSaveStates.append(marker.state)
            let result = storedSaveResults.isEmpty
                ? ScriptedMarkerResult.success
                : storedSaveResults.removeFirst()
            guard result == .success else {
                throw ScriptedMarkerError.unavailable
            }
            storedMarker = marker
            storedSavedStates.append(marker.state)
        }
    }

    func removeIfPresent() throws {
        recorder?.append(.markerRemove)
        try lock.withLock {
            storedRemoveCallCount += 1
            let result = storedRemoveResults.isEmpty
                ? ScriptedMarkerResult.success
                : storedRemoveResults.removeFirst()
            guard result == .success else {
                throw ScriptedMarkerError.unavailable
            }
            storedMarker = nil
        }
    }
}

private actor ScriptedAPIKeyStore: OpenAIAPIKeyStoring {
    enum Call: Equatable, Sendable {
        case save
        case load
        case remove
    }

    private(set) var storedKey: String?
    private(set) var calls: [Call] = []
    private var saveError: OpenAIAPIKeyKeychainStorageError?
    private var loadError: OpenAIAPIKeyKeychainStorageError?
    private var removeError: OpenAIAPIKeyKeychainStorageError?
    private let saveIsCancelled: Bool
    private let saveGate: AsyncCallGate?
    private let loadGate: AsyncCallGate?
    private let removeGate: AsyncCallGate?
    private let recorder: CredentialEventRecorder?

    init(
        storedKey: String? = nil,
        saveError: OpenAIAPIKeyKeychainStorageError? = nil,
        loadError: OpenAIAPIKeyKeychainStorageError? = nil,
        removeError: OpenAIAPIKeyKeychainStorageError? = nil,
        saveIsCancelled: Bool = false,
        saveGate: AsyncCallGate? = nil,
        loadGate: AsyncCallGate? = nil,
        removeGate: AsyncCallGate? = nil,
        recorder: CredentialEventRecorder? = nil
    ) {
        self.storedKey = storedKey
        self.saveError = saveError
        self.loadError = loadError
        self.removeError = removeError
        self.saveIsCancelled = saveIsCancelled
        self.saveGate = saveGate
        self.loadGate = loadGate
        self.removeGate = removeGate
        self.recorder = recorder
    }

    func saveOrReplaceAPIKey(_ candidate: String) async throws {
        calls.append(.save)
        recorder?.append(.keychainSave)
        await saveGate?.enter()
        if saveIsCancelled {
            throw CancellationError()
        }
        if let saveError {
            throw saveError
        }
        storedKey = candidate
    }

    func loadAPIKey() async throws -> String? {
        calls.append(.load)
        recorder?.append(.keychainLoad)
        await loadGate?.enter()
        if let loadError {
            throw loadError
        }
        return storedKey
    }

    func removeAPIKey() async throws {
        calls.append(.remove)
        recorder?.append(.keychainRemove)
        await removeGate?.enter()
        if let removeError {
            throw removeError
        }
        storedKey = nil
    }

    func setSaveError(_ error: OpenAIAPIKeyKeychainStorageError?) {
        saveError = error
    }

    func setLoadError(_ error: OpenAIAPIKeyKeychainStorageError?) {
        loadError = error
    }
}

private actor AsyncCallGate {
    private var isOpen = false
    private var didEnter = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        didEnter = true
        let entryWaiters = self.entryWaiters
        self.entryWaiters.removeAll()
        for waiter in entryWaiters {
            waiter.resume()
        }

        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            openWaiters.append(continuation)
        }
    }

    func waitUntilEntered() async {
        guard !didEnter else {
            return
        }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let openWaiters = self.openWaiters
        self.openWaiters.removeAll()
        for waiter in openWaiters {
            waiter.resume()
        }
    }
}
