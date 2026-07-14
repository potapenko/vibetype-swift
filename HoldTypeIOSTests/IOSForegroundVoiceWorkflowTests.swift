import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSForegroundVoiceWorkflowTests {
    @Test
    func sharedControllerCarriesExactSceneLeaseAndFinishAuthority() async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            acquireLease: false
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.workflow.client,
            sceneRegistry: fixture.registry
        )
        await controller.activate()
        let start = try #require(
            controller.actionCommands.first {
                $0.action == .startStandard
            }
        )

        #expect(controller.submit(start) == .unavailable)
        #expect(controller.submit(start, from: fixture.facade) == .accepted)
        try await waitUntil { controller.presentation.phase == .listening }
        let finish = try #require(
            controller.actionCommands.first {
                $0.action == .finishUtterance
            }
        )
        #expect(controller.submit(finish) == .accepted)
        try await waitUntil { controller.presentation.phase == .inactive }

        #expect(controller.presentation.failure == .tooShort)
        #expect(fixture.stopReasons == [.done])
        #expect(fixture.facade.promptPresentation == .available)
    }

    @Test
    func providerConsentInvalidationInterruptsAndPreservesCaptureDiscard()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            preserveCaptureOnInterruptedStop: true,
            acquireLease: false
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.workflow.client,
            sceneRegistry: fixture.registry
        )
        await controller.activate()
        let start = try #require(
            controller.actionCommands.first {
                $0.action == .startStandard
            }
        )
        #expect(controller.submit(start, from: fixture.facade) == .accepted)
        try await waitUntil { controller.presentation.phase == .listening }

        controller.providerConsentDidInvalidate()
        try await waitUntil { controller.presentation.phase == .inactive }

        #expect(fixture.stopReasons == [.interrupted])
        #expect(
            controller.presentation.recovery == .captureDiscardOnly
        )
        #expect(
            controller.presentation.availableActions == [.discard]
        )
        #expect(!fixture.events.contains("provider-process"))
        #expect(!fixture.events.contains("recording-stop-cancelled"))
    }

    @Test
    func startRunsFrozenPreflightOrderAndDoneReachesExactRecorder() async throws {
        let fixture = try await WorkflowFixture(permission: .undetermined)
        let token = IOSForegroundVoiceWorkflowAttemptToken()
        let task = Task { @MainActor in
            await fixture.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: fixture.lease
                ),
                token: token,
                progress: { progress in
                    fixture.events.record("progress-\(progress)")
                }
            )
        }

        try await waitUntil {
            fixture.events.contains("recording-start")
        }
        #expect(fixture.workflow.finishUtterance(token) == .accepted)
        let resolution = await task.value

        #expect(resolution.failure == .tooShort)
        #expect(fixture.stopReasons == [.done])
        #expect(fixture.audioWasDeactivated)
        #expect(fixture.finalizationFinishCount == 1)
        #expect(fixture.permissionRequestCount == 1)
        #expect(fixture.registry.snapshot.isForegroundActive)
        #expect(fixture.facade.promptPresentation == .available)

        let values = fixture.events.values
        let consentIndex = try #require(
            values.firstIndex(of: "consent-observe")
        )
        #expect(values[..<consentIndex].filter { $0 == "settings-load" }.count == 1)
        #expect(values[..<consentIndex].filter { $0 == "library-load" }.count == 1)
        assertOrdered(
            [
                "capture-reconcile",
                "pending-load",
                "latest-load",
                "settings-load",
                "library-load",
                "consent-observe",
                "consent-continue",
                "credential-resolve",
                "permission-request",
                "history-stop",
                "audio-activate",
                "start-boundary",
                "input-freeze",
                "recording-make",
                "recording-start",
                "recording-stop-done",
                "finalization-finish",
                "audio-deactivate",
            ],
            in: values
        )
        #expect(!values.contains("provider-process"))
        #expect(!values.contains { $0.hasPrefix("lifecycle-recover-") })
    }

    @Test
    func lifecycleRecoveryOwnsExactOrderAndForegroundOpportunity()
        async throws {
        let fixture = try await WorkflowFixture(permission: .granted)

        let result = await fixture.workflow.recoverLifecycle(
            .foregroundOpportunity
        )

        #expect(result.disposition == .complete)
        assertOrdered(
            [
                "capture-reconcile",
                "lifecycle-recover-foreground",
                "pending-load",
                "latest-load",
            ],
            in: fixture.events.values
        )
        #expect(fixture.events.count("capture-reconcile") == 1)
        #expect(fixture.events.count("lifecycle-recover-foreground") == 1)
        #expect(fixture.events.count("pending-load") == 1)
        #expect(fixture.events.count("latest-load") == 1)
    }

    @Test
    func freshRootProcessLaunchPublishesReadyOnItsFirstOpportunity()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            preRecoverHistory: false,
            useActualLifecycleRecovery: true
        )

        let result = await fixture.workflow.recoverLifecycle(.processLaunch)

        #expect(result.disposition == .complete)
        #expect(result.observation.setup == .ready)
        #expect(result.observation.recovery == .none)
        #expect(result.observation.latestAvailability == .absent)
        assertOrdered(
            [
                "capture-reconcile",
                "lifecycle-recover-process-launch",
                "pending-load",
                "latest-load",
                "settings-load",
                "library-load",
            ],
            in: fixture.events.values
        )
        #expect(fixture.events.count("capture-reconcile") == 1)
        for forbidden in [
            "consent-observe",
            "credential-resolve",
            "permission-read",
            "permission-request",
            "audio-activate",
            "recording-make",
            "provider-process",
        ] {
            #expect(fixture.events.count(forbidden) == 0)
        }
    }


    @Test
    func secondBlockedUnknownCaptureRemainsBlockedWithoutLoop() async throws {
        let blocked = IOSV1ForegroundVoiceCaptureRecoveryObservation.blocked
        let fixture = try await WorkflowFixture(
            permission: .granted,
            captureRecoveryObservations: [blocked, blocked]
        )

        let result = await fixture.workflow.recoverLifecycle(.processLaunch)

        #expect(result.disposition == .pendingLocalRecovery)
        #expect(result.observation.recovery == .blocked)
        #expect(fixture.events.count("capture-reconcile") == 2)
        #expect(fixture.events.count("pending-load") == 1)
        #expect(fixture.events.count("latest-load") == 1)
        #expect(fixture.events.count("settings-load") == 0)
        #expect(fixture.events.count("library-load") == 0)
    }

    @Test
    func cancellationDuringSecondCaptureRecheckStopsBeforeDurableLoads()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            suspensionTrigger: WorkflowEventTrigger(
                "capture-reconcile",
                occurrence: 2
            ),
            preRecoverHistory: false,
            useActualLifecycleRecovery: true,
            captureRecoveryObservations: [.blocked, .blocked]
        )
        let task = Task {
            await fixture.workflow.recoverLifecycle(.processLaunch)
        }
        try await waitUntil {
            fixture.events.count("capture-reconcile") == 2
        }

        task.cancel()
        let result = await task.value

        #expect(result.disposition == .pendingLocalRecovery)
        #expect(fixture.events.contains("capture-reconcile-cancelled"))
        #expect(fixture.events.count("pending-load") == 0)
        #expect(fixture.events.count("latest-load") == 0)
        #expect(fixture.events.count("settings-load") == 0)
        #expect(fixture.events.count("library-load") == 0)
    }

    @Test
    func cancelledCaptureReconcileCannotStartHistoryOrDurableLoads()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            suspensionTrigger: WorkflowEventTrigger("capture-reconcile")
        )
        let task = Task {
            await fixture.workflow.recoverLifecycle(.processLaunch)
        }
        try await waitUntil {
            fixture.events.contains("capture-reconcile")
        }

        task.cancel()
        let result = await task.value

        #expect(result.disposition == .pendingLocalRecovery)
        #expect(fixture.events.contains("capture-reconcile-cancelled"))
        #expect(
            !fixture.events.values.contains {
                $0.hasPrefix("lifecycle-recover-")
            }
        )
        #expect(fixture.events.count("pending-load") == 0)
        #expect(fixture.events.count("latest-load") == 0)
    }

    @Test
    func cancelledPendingLoadCannotStartLatestLoad() async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            suspensionTrigger: WorkflowEventTrigger("pending-load")
        )
        let task = Task {
            await fixture.workflow.recoverLifecycle(.processLaunch)
        }
        try await waitUntil { fixture.events.contains("pending-load") }

        task.cancel()
        let result = await task.value

        #expect(result.disposition == .pendingLocalRecovery)
        #expect(fixture.events.contains("pending-load-cancelled"))
        #expect(fixture.events.count("latest-load") == 0)
        #expect(fixture.events.count("settings-load") == 0)
    }

    @Test
    func cancelledHistoryRecoveryCannotStartPendingOrLatestLoads()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            suspensionTrigger: WorkflowEventTrigger(
                "lifecycle-recover-process-launch"
            )
        )
        let task = Task {
            await fixture.workflow.recoverLifecycle(.processLaunch)
        }
        try await waitUntil {
            fixture.events.contains("lifecycle-recover-process-launch")
        }

        task.cancel()
        let result = await task.value

        #expect(result.disposition == .pendingLocalRecovery)
        #expect(
            fixture.events.contains(
                "lifecycle-recover-process-launch-cancelled"
            )
        )
        #expect(fixture.events.count("pending-load") == 0)
        #expect(fixture.events.count("latest-load") == 0)
    }

    @Test
    func cancelledSettingsLoadCannotStartLibraryLoad() async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            suspensionTrigger: WorkflowEventTrigger("settings-load")
        )
        let task = Task {
            await fixture.workflow.recoverLifecycle(.foregroundOpportunity)
        }
        try await waitUntil { fixture.events.contains("settings-load") }

        task.cancel()
        let result = await task.value

        #expect(result.disposition == .pendingLocalRecovery)
        #expect(fixture.events.contains("settings-load-cancelled"))
        #expect(fixture.events.count("library-load") == 0)
    }

    @Test
    func lifecycleLocalConfigurationLoadFailureIsPendingAndFailClosed()
        async throws {
        let fixture = try await WorkflowFixture(
            settingsLoads: [.failure],
            permission: .granted
        )

        let result = await fixture.workflow.recoverLifecycle(
            .foregroundOpportunity
        )

        #expect(result.disposition == .pendingLocalRecovery)
        #expect(result.observation.setup == .unavailable)
        #expect(fixture.events.count("settings-load") == 1)
        #expect(fixture.events.count("library-load") == 0)
    }

    @Test
    func invalidTranslationStopsAfterSettingsAndLibrary() async throws {
        let fixture = try await WorkflowFixture(
            settings: .defaults,
            permission: .granted
        )
        let resolution = await fixture.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .translate,
                sceneLease: fixture.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )

        #expect(resolution.observation.setup == .needsSetup(.translation))
        let values = fixture.events.values
        #expect(values.contains("settings-load"))
        #expect(values.contains("library-load"))
        #expect(!values.contains("consent-observe"))
        #expect(!values.contains("credential-resolve"))
        #expect(!values.contains("permission-read"))
        #expect(!values.contains("audio-activate"))
        #expect(!values.contains("recording-make"))
    }

    @Test
    func lastActiveSceneLossInterruptsCaptureAndNeverProcesses() async throws {
        let fixture = try await WorkflowFixture(permission: .granted)
        let token = IOSForegroundVoiceWorkflowAttemptToken()
        let task = Task { @MainActor in
            await fixture.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: fixture.lease
                ),
                token: token,
                progress: { _ in }
            )
        }

        try await waitUntil {
            fixture.events.contains("recording-start")
        }
        #expect(fixture.facade.updateActivity(.inactive) == .accepted)
        let resolution = await task.value

        #expect(resolution.outcome == .interrupted)
        #expect(fixture.stopReasons == [.interrupted])
        #expect(fixture.audioWasDeactivated)
        #expect(!fixture.events.contains("provider-process"))
        #expect(fixture.workflow.finishUtterance(token) == .unavailable)
    }

    @Test
    func providerFreeObservationProjectsDiscardOnlyCaptureRecovery() async throws {
        let fixture = try await WorkflowFixture(permission: .granted)
        let capture = try await fixture.persistenceOwner.createCapture(
            attemptID: UUID(),
            outputIntent: .standard
        )
        capture.release()

        let observation = await fixture.workflow.client.observe()

        #expect(observation.recovery == .captureDiscardOnly)
        #expect(!fixture.events.contains("credential-resolve"))
        #expect(!fixture.events.contains("permission-read"))
        #expect(!fixture.events.contains("provider-process"))
    }

    @Test
    func durableRecoveryBlocksSettingsLibraryAndProviderPreflight() async throws {
        let fixture = try await WorkflowFixture(permission: .granted)
        let capture = try await fixture.persistenceOwner.createCapture(
            attemptID: UUID(),
            outputIntent: .standard
        )
        capture.release()

        let resolution = await fixture.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: fixture.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )

        #expect(resolution.observation.recovery == .captureDiscardOnly)
        #expect(!fixture.events.contains("settings-load"))
        #expect(!fixture.events.contains("library-load"))
        #expect(!fixture.events.contains("consent-observe"))
        #expect(!fixture.events.contains("credential-resolve"))
    }

    @Test
    func settingsFailureBlocksLibraryAndEveryLaterBoundary() async throws {
        let fixture = try await WorkflowFixture(
            settingsLoads: [.failure],
            permission: .granted
        )

        _ = await fixture.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: fixture.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )

        #expect(fixture.events.contains("settings-load"))
        #expect(!fixture.events.contains("library-load"))
        #expect(!fixture.events.contains("consent-observe"))
        #expect(!fixture.events.contains("permission-read"))
        #expect(!fixture.events.contains("audio-activate"))
    }

    @Test
    func invalidStandardConfigurationBlocksBeforeConsent() async throws {
        var settings = IOSAppSettings.defaults
        settings.transcriptionConfiguration = TranscriptionConfiguration(
            language: .custom,
            customLanguageCode: "invalid!"
        )
        let fixture = try await WorkflowFixture(
            settings: settings,
            permission: .granted
        )

        let resolution = await fixture.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: fixture.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )

        #expect(resolution.observation.setup == .needsSetup(.transcription))
        #expect(fixture.events.contains("library-load"))
        #expect(!fixture.events.contains("consent-observe"))
    }

    @Test
    func consentDeclineAndStaleAcceptanceNeverReachCredential() async throws {
        let declined = try await WorkflowFixture(
            permission: .granted,
            consentContinuationAllowed: false
        )
        _ = await declined.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: declined.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(declined.events.contains("consent-continue"))
        #expect(!declined.events.contains("credential-resolve"))

        let stale = try await WorkflowFixture(
            permission: .granted,
            consentRevalidation: [false]
        )
        _ = await stale.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: stale.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(stale.events.contains("consent-revalidate"))
        #expect(!stale.events.contains("credential-resolve"))
    }

    @Test
    func missingAndStaleCredentialsBlockPermissionAndHistory() async throws {
        let missing = try await WorkflowFixture(
            permission: .granted,
            credentialAvailable: false
        )
        let missingResolution = await missing.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: missing.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(missingResolution.observation.setup == .needsSetup(.openAI))
        #expect(!missing.events.contains("permission-read"))

        let stale = try await WorkflowFixture(
            permission: .granted,
            credentialRevalidation: [false]
        )
        _ = await stale.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: stale.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(stale.events.contains("permission-read"))
        #expect(!stale.events.contains("history-stop"))
        #expect(!stale.events.contains("audio-activate"))
    }

    @Test
    func deniedAndTimedOutPermissionNeverReachHistoryOrAudio() async throws {
        let denied = try await WorkflowFixture(permission: .denied)
        _ = await denied.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: denied.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(!denied.events.contains("permission-request"))
        #expect(!denied.events.contains("history-stop"))

        let timedOut = try await WorkflowFixture(
            permission: .undetermined,
            permissionOutcome: .timedOut
        )
        _ = await timedOut.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: timedOut.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(timedOut.permissionRequestCount == 1)
        #expect(!timedOut.events.contains("history-stop"))
        #expect(!timedOut.events.contains("audio-activate"))
    }

    @Test
    func historyCueSceneAndRecorderShortCircuitsStayFailClosed() async throws {
        let history = try await WorkflowFixture(
            permission: .granted,
            historyStops: false
        )
        _ = await history.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: history.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(!history.events.contains("audio-activate"))

        let cue = try await WorkflowFixture(
            permission: .granted,
            startBoundarySucceeds: false
        )
        _ = await cue.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: cue.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(cue.events.contains("audio-deactivate"))
        #expect(!cue.events.contains("recording-make"))

        let scene = try await WorkflowFixture(
            permission: .granted,
            deactivateSceneAtStartBoundary: true
        )
        _ = await scene.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: scene.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(scene.events.contains("start-boundary-cancel"))
        #expect(!scene.events.contains("recording-make"))

        let recorder = try await WorkflowFixture(
            permission: .granted,
            recordingIsActive: false
        )
        _ = await recorder.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: recorder.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(recorder.events.contains("recording-start"))
        #expect(recorder.stopReasons == [.interrupted])
        #expect(!recorder.events.contains("provider-process"))
    }

    @Test
    func postPermissionSettingsAndConsentRevalidationBlockHistory() async throws {
        var changed = IOSAppSettings.defaults
        changed.localTextCleanupEnabled = false
        let settings = try await WorkflowFixture(
            settingsLoads: [
                .value(.defaults),
                .value(changed),
            ],
            permission: .granted
        )
        _ = await settings.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: settings.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(!settings.events.contains("history-stop"))

        let consent = try await WorkflowFixture(
            permission: .granted,
            consentRevalidation: [true, false]
        )
        _ = await consent.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: consent.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(!consent.events.contains("history-stop"))
    }

    @Test
    func postCueLibraryCredentialAndSceneRevalidationBlockRecorder() async throws {
        var changedLibrary = IOSLibraryContent.defaults
        changedLibrary.replacementRules = [
            TextReplacementRule(search: "alpha", replacement: "beta")
        ]
        let library = try await WorkflowFixture(
            libraryLoads: [
                .value(.defaults), .value(.defaults),
                .value(changedLibrary),
            ],
            permission: .granted
        )
        _ = await library.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: library.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(library.events.contains("start-boundary"))
        #expect(!library.events.contains("recording-make"))

        let credential = try await WorkflowFixture(
            permission: .granted,
            credentialRevalidation: [true, false]
        )
        _ = await credential.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: credential.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(credential.events.contains("start-boundary"))
        #expect(!credential.events.contains("recording-make"))

        let scene = try await WorkflowFixture(
            permission: .granted,
            deactivateSceneAtStartBoundary: true
        )
        _ = await scene.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: scene.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(!scene.events.contains("recording-make"))
    }

    @Test
    func tailIsPreemptedByInterruptionAndMaximumDuration() async throws {
        var settings = IOSAppSettings.defaults
        settings.voiceSessionPreferences.recordingStopTailDuration = .seconds2

        let interrupted = try await WorkflowFixture(
            settings: settings,
            permission: .granted
        )
        let interruptedToken = IOSForegroundVoiceWorkflowAttemptToken()
        let interruptedTask = Task { @MainActor in
            await interrupted.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: interrupted.lease
                ),
                token: interruptedToken,
                progress: { _ in }
            )
        }
        try await waitUntil {
            interrupted.events.contains("recording-start")
        }
        #expect(
            interrupted.workflow.finishUtterance(interruptedToken)
                == .accepted
        )
        await Task.yield()
        _ = interrupted.facade.updateActivity(.inactive)
        _ = await interruptedTask.value
        #expect(interrupted.stopReasons == [.interrupted])

        let maximum = try await WorkflowFixture(
            settings: settings,
            permission: .granted
        )
        let maximumToken = IOSForegroundVoiceWorkflowAttemptToken()
        let maximumTask = Task { @MainActor in
            await maximum.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: maximum.lease
                ),
                token: maximumToken,
                progress: { _ in }
            )
        }
        try await waitUntil { maximum.events.contains("recording-start") }
        #expect(maximum.workflow.finishUtterance(maximumToken) == .accepted)
        await Task.yield()
        maximum.emitTerminal(.maximumDuration)
        _ = await maximumTask.value
        #expect(maximum.stopReasons == [.maximumDuration])
    }

    @Test
    func controllerCancelPreemptsConfiguredTail() async throws {
        var settings = IOSAppSettings.defaults
        settings.voiceSessionPreferences.recordingStopTailDuration = .seconds2
        let fixture = try await WorkflowFixture(
            settings: settings,
            permission: .granted,
            acquireLease: false
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.workflow.client,
            sceneRegistry: fixture.registry
        )
        await controller.activate()
        let start = try #require(controller.actionCommands.first {
            $0.action == .startStandard
        })
        #expect(controller.submit(start, from: fixture.facade) == .accepted)
        try await waitUntil { controller.presentation.phase == .listening }
        let finish = try #require(controller.actionCommands.first {
            $0.action == .finishUtterance
        })
        #expect(controller.submit(finish) == .accepted)
        let cancel = try #require(controller.actionCommands.first {
            $0.action == .cancelUtterance
        })
        #expect(controller.submit(cancel) == .accepted)
        try await waitUntil { controller.presentation.phase == .inactive }
        #expect(fixture.stopReasons == [.cancelled])
    }

    @Test
    func finalizationExpirationAndStopCueOrderingNeverDispatchEarly() async throws {
        let expired = try await WorkflowFixture(
            permission: .granted,
            completedCapture: true,
            expireFinalizationImmediately: true,
            preacceptConsent: true
        )
        let expiredToken = IOSForegroundVoiceWorkflowAttemptToken()
        let expiredTask = Task { @MainActor in
            await expired.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: expired.lease
                ),
                token: expiredToken,
                progress: { _ in }
            )
        }
        try await waitUntil { expired.events.contains("recording-start") }
        #expect(expired.workflow.finishUtterance(expiredToken) == .accepted)
        _ = await expiredTask.value
        #expect(!expired.events.contains("pending-prepare"))
        #expect(!expired.events.contains("provider-process"))

        let ordered = try await WorkflowFixture(
            permission: .granted,
            completedCapture: true,
            preacceptConsent: true
        )
        let orderedToken = IOSForegroundVoiceWorkflowAttemptToken()
        let orderedTask = Task { @MainActor in
            await ordered.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: ordered.lease
                ),
                token: orderedToken,
                progress: { _ in }
            )
        }
        try await waitUntil { ordered.events.contains("recording-start") }
        #expect(ordered.workflow.finishUtterance(orderedToken) == .accepted)
        _ = await orderedTask.value
        assertOrdered(
            [
                "recording-stop-done",
                "stop-boundary",
                "audio-deactivate",
                "pending-prepare",
                "provider-process",
            ],
            in: ordered.events.values
        )
    }

    @Test
    func aggregateLossCancelsInitialAndRetryProcessorWork() async throws {
        let initial = try await WorkflowFixture(
            permission: .granted,
            completedCapture: true,
            processorSuspendsUntilCancelled: true,
            preacceptConsent: true
        )
        let initialToken = IOSForegroundVoiceWorkflowAttemptToken()
        let initialTask = Task { @MainActor in
            await initial.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: initial.lease
                ),
                token: initialToken,
                progress: { _ in }
            )
        }
        try await waitUntil { initial.events.contains("recording-start") }
        #expect(initial.workflow.finishUtterance(initialToken) == .accepted)
        try await waitUntil { initial.events.contains("provider-process") }
        _ = initial.facade.updateActivity(.inactive)
        let initialResolution = await initialTask.value
        #expect(initialResolution.observation.recovery == .pendingRetryOrDiscard)

        let retry = try await WorkflowFixture(
            permission: .granted,
            processorSuspendsUntilCancelled: true,
            preacceptConsent: true
        )
        _ = try await retry.seedPending()
        let controller = IOSForegroundVoiceController(
            client: retry.workflow.client,
            sceneRegistry: retry.registry
        )
        await controller.activate()
        let retryCommand = try #require(controller.actionCommands.first {
            $0.action == .retryPending
        })
        #expect(controller.submit(retryCommand) == .accepted)
        try await waitUntil { retry.events.contains("provider-process") }
        _ = retry.facade.updateActivity(.inactive)
        try await waitUntil { controller.presentation.phase == .inactive }
        #expect(controller.presentation.recovery == .pendingRetryOrDiscard)
        #expect(controller.presentation.outcome == .recoverableFailure)
    }

    @Test
    func pendingDiscardAndRetryMappingRemainProviderFreeUntilExplicitRetry()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            preacceptConsent: true
        )
        _ = try await fixture.seedPending()
        let controller = IOSForegroundVoiceController(
            client: fixture.workflow.client,
            sceneRegistry: fixture.registry
        )
        await controller.activate()
        #expect(controller.presentation.recovery == .pendingRetryOrDiscard)
        #expect(!fixture.events.contains("provider-process"))

        let discard = try #require(controller.actionCommands.first {
            $0.action == .discard
        })
        #expect(controller.submit(discard) == .accepted)
        try await waitUntil { fixture.events.contains("pending-discard") }
        try await waitUntil { controller.presentation.recovery == .none }
        #expect(!fixture.events.contains("provider-process"))
    }


    @Test
    func typedPreflightFailuresRemainDistinctAndStopImmediately() async throws {
        let denied = try await WorkflowFixture(permission: .denied)
        let deniedResolution = await denied.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: denied.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(deniedResolution.failure == .microphonePermissionDenied)
        #expect(deniedResolution.observation.setup == .needsSetup(
            .microphoneAndPrivacy
        ))

        let unavailable = try await WorkflowFixture(permission: .unavailable)
        let unavailableResolution = await unavailable.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: unavailable.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(unavailableResolution.failure == .microphoneUnavailable)
        #expect(unavailableResolution.observation.setup == .unavailable)

        let timedOut = try await WorkflowFixture(
            permission: .undetermined,
            permissionOutcome: .timedOut,
            reactivateSceneAfterPermission: false
        )
        let timedOutResolution = await timedOut.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: timedOut.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(timedOutResolution.failure == .microphonePermissionTimedOut)
        #expect(!timedOut.events.contains("history-stop"))

        let cancelled = try await WorkflowFixture(
            permission: .undetermined,
            permissionOutcome: .cancelled,
            reactivateSceneAfterPermission: false
        )
        let cancelledResolution = await cancelled.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: cancelled.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(cancelledResolution.failure == nil)
        #expect(!cancelled.events.contains("history-stop"))

        let missingCredential = try await WorkflowFixture(
            permission: .granted,
            credentialResolutions: [.needsSetup]
        )
        let missingResolution = await missingCredential.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: missingCredential.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(missingResolution.failure == nil)
        #expect(missingResolution.observation.setup == .needsSetup(.openAI))

        let secureUnavailable = try await WorkflowFixture(
            permission: .granted,
            credentialResolutions: [.unavailable]
        )
        let secureResolution = await secureUnavailable.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: secureUnavailable.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(secureResolution.failure == .unavailable)
        #expect(secureResolution.observation.setup == .unavailable)

        let settingsIO = try await WorkflowFixture(
            settingsLoads: [.failure],
            permission: .granted
        )
        let settingsResolution = await settingsIO.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: settingsIO.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(settingsResolution.failure == .localRecovery)

        let libraryIO = try await WorkflowFixture(
            libraryLoads: [.failure],
            permission: .granted
        )
        let libraryResolution = await libraryIO.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: libraryIO.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(libraryResolution.failure == .localRecovery)

        var invalidSettings = IOSAppSettings.defaults
        invalidSettings.transcriptionConfiguration = TranscriptionConfiguration(
            language: .custom,
            customLanguageCode: "x-invalid"
        )
        let invalid = try await WorkflowFixture(
            settings: invalidSettings,
            permission: .granted
        )
        let invalidResolution = await invalid.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: invalid.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(invalidResolution.failure == .unavailable)
    }

    @Test
    func foregroundLossDuringHistoryOrRecorderCreationStartsNoAudioCapture()
        async throws {
        let history = try await WorkflowFixture(
            permission: .granted,
            deactivateSceneDuringHistoryStop: true
        )
        _ = await history.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: history.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(history.events.contains("history-stop"))
        #expect(!history.events.contains("audio-activate"))
        #expect(!history.events.contains("recording-make"))

        let recorder = try await WorkflowFixture(
            permission: .granted,
            deactivateSceneDuringMakeRecording: true
        )
        _ = await recorder.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: recorder.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(recorder.events.contains("recording-make"))
        #expect(!recorder.events.contains("recording-start"))
        #expect(recorder.stopReasons == [.interrupted])
    }

    @Test
    func exactOutputOnlyRouteContinuesWithFullLiveProof() async throws {
        let continuing = try await WorkflowFixture(
            permission: .granted,
            audioFreezeResults: [true, true, true],
            recordingActiveValues: [true, true]
        )
        let continuingToken = IOSForegroundVoiceWorkflowAttemptToken()
        let continuingTask = Task { @MainActor in
            await continuing.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: continuing.lease
                ),
                token: continuingToken,
                progress: { _ in }
            )
        }
        try await waitUntil(timeout: .seconds(5)) {
            continuing.events.contains("recording-start")
        }
        continuing.emitAudio(.routeNeedsRevalidation)
        await Task.yield()
        #expect(continuing.stopReasons.isEmpty)
        #expect(continuing.workflow.finishUtterance(continuingToken) == .accepted)
        _ = await continuingTask.value
    }

    @Test
    func outputOnlyRouteStopsWhenRecorderIsNotActive() async throws {
        let inactive = try await WorkflowFixture(
            permission: .granted,
            recordingActiveValues: [true, false]
        )
        let inactiveTask = Task { @MainActor in
            await inactive.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: inactive.lease
                ),
                token: IOSForegroundVoiceWorkflowAttemptToken(),
                progress: { _ in }
            )
        }
        try await waitUntil(timeout: .seconds(5)) {
            inactive.events.contains("recording-start")
        }
        inactive.emitAudio(.routeNeedsRevalidation)
        _ = await inactiveTask.value
        #expect(inactive.stopReasons == [.interrupted])
    }

    @Test
    func outputOnlyRouteStopsWhenFrozenInputRevalidationFails() async throws {
        let invalidInput = try await WorkflowFixture(
            permission: .granted,
            audioFreezeResults: [true, true, false],
            recordingActiveValues: [true, true]
        )
        let invalidInputTask = Task { @MainActor in
            await invalidInput.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: invalidInput.lease
                ),
                token: IOSForegroundVoiceWorkflowAttemptToken(),
                progress: { _ in }
            )
        }
        try await waitUntil(timeout: .seconds(5)) {
            invalidInput.events.contains("recording-start")
        }
        invalidInput.emitAudio(.routeNeedsRevalidation)
        _ = await invalidInputTask.value
        #expect(invalidInput.stopReasons == [.interrupted])
    }

    @Test
    func initiatingSceneOwnershipEndsAfterPreflightButAggregateLossStillStops()
        async throws {
        let listening = try await WorkflowFixture(permission: .granted)
        let second = listening.registry.registerScene(initialActivity: .active)
        let listeningToken = IOSForegroundVoiceWorkflowAttemptToken()
        let listeningTask = Task { @MainActor in
            await listening.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: listening.lease
                ),
                token: listeningToken,
                progress: { _ in }
            )
        }
        try await waitUntil { listening.events.contains("recording-start") }
        #expect(listening.facade.promptPresentation == .available)
        #expect(listening.facade.unregister() == .accepted)
        await Task.yield()
        #expect(listening.stopReasons.isEmpty)
        #expect(listening.workflow.finishUtterance(listeningToken) == .accepted)
        _ = await listeningTask.value
        #expect(second.updateActivity(.inactive) == .accepted)

        let processing = try await WorkflowFixture(
            permission: .granted,
            completedCapture: true,
            processorSuspendsUntilCancelled: true,
            preacceptConsent: true
        )
        let processingSecond = processing.registry.registerScene(
            initialActivity: .active
        )
        let processingToken = IOSForegroundVoiceWorkflowAttemptToken()
        let processingTask = Task { @MainActor in
            await processing.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: processing.lease
                ),
                token: processingToken,
                progress: { _ in }
            )
        }
        try await waitUntil { processing.events.contains("recording-start") }
        #expect(
            processing.workflow.finishUtterance(processingToken) == .accepted
        )
        try await waitUntil { processing.events.contains("provider-process") }
        #expect(processing.facade.unregister() == .accepted)
        await Task.yield()
        #expect(processingSecond.updateActivity(.inactive) == .accepted)
        let processingResolution = await processingTask.value
        #expect(processingResolution.outcome == .recoverableFailure)
        #expect(processingResolution.observation.recovery == .pendingRetryOrDiscard)
    }

    @Test
    func expirationAfterAwaitedStopCueNeverPreparesPending() async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            completedCapture: true,
            expireFinalizationAtStopBoundary: true,
            preacceptConsent: true
        )
        let token = IOSForegroundVoiceWorkflowAttemptToken()
        let task = Task { @MainActor in
            await fixture.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: fixture.lease
                ),
                token: token,
                progress: { _ in }
            )
        }
        try await waitUntil { fixture.events.contains("recording-start") }
        #expect(fixture.workflow.finishUtterance(token) == .accepted)
        let resolution = await task.value
        #expect(fixture.events.contains("stop-boundary"))
        #expect(!fixture.events.contains("pending-prepare"))
        #expect(!fixture.events.contains("provider-process"))
        #expect(resolution.failure == .localRecovery)
    }

    @Test
    func terminalEventDuringRecorderStartIsObservedWithoutWindow() async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            terminalDuringRecordingStart: .interrupted
        )
        let resolution = await fixture.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: fixture.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(fixture.events.contains("recording-start"))
        #expect(fixture.stopReasons == [.interrupted])
        #expect(resolution.outcome == .interrupted)
    }

    @Test
    func captureHandoffIsSingleUseAndReleasesExactlyOnceOnFailure()
        async throws {
        var prepareCount = 0
        var releaseCount = 0
        let successful = IOSForegroundVoiceWorkflowCaptureHandoff(
            prepare: { configuration in
                prepareCount += 1
                return try makePendingRecording(
                    outputIntent: .standard,
                    phase: .readyForTranscription,
                    configuration: configuration
                )
            },
            release: { releaseCount += 1 }
        )
        _ = try await successful.preparePending(
            transcriptionConfiguration: .defaults
        )
        do {
            _ = try await successful.preparePending(
                transcriptionConfiguration: .defaults
            )
            Issue.record("Second prepare unexpectedly succeeded")
        } catch {}
        successful.release()
        #expect(prepareCount == 1)
        #expect(releaseCount == 0)

        var failingPrepareCount = 0
        var failingReleaseCount = 0
        let failing = IOSForegroundVoiceWorkflowCaptureHandoff(
            prepare: { _ in
                failingPrepareCount += 1
                throw WorkflowFixtureError.configuredFailure
            },
            release: { failingReleaseCount += 1 }
        )
        do {
            _ = try await failing.preparePending(
                transcriptionConfiguration: .defaults
            )
            Issue.record("Failing prepare unexpectedly succeeded")
        } catch {}
        failing.release()
        #expect(failingPrepareCount == 1)
        #expect(failingReleaseCount == 1)
    }

    @Test
    func everyRejectedStartPathRetiresItsExactSceneLease() async throws {
        let invalid = try await WorkflowFixture(permission: .granted)
        let foreignRegistry = IOSVoiceSceneRegistry()
        let foreignFacade = foreignRegistry.registerScene(
            initialActivity: .active
        )
        let foreignLease = try #require(foreignFacade.acquireStartLease())
        _ = await invalid.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: foreignLease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        let replacementForeignLease = try #require(
            foreignFacade.acquireStartLease()
        )
        replacementForeignLease.finish()

        let busy = try await WorkflowFixture(permission: .granted)
        let busyToken = IOSForegroundVoiceWorkflowAttemptToken()
        let busyTask = Task { @MainActor in
            await busy.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: busy.lease
                ),
                token: busyToken,
                progress: { _ in }
            )
        }
        try await waitUntil { busy.events.contains("recording-start") }
        let busyScene = busy.registry.registerScene(initialActivity: .active)
        let rejectedLease = try #require(busyScene.acquireStartLease())
        _ = await busy.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: rejectedLease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        let replacementBusyLease = try #require(
            busyScene.acquireStartLease()
        )
        replacementBusyLease.finish()
        #expect(busy.workflow.finishUtterance(busyToken) == .accepted)
        _ = await busyTask.value

        let released = try await WorkflowFixture(
            permission: .granted,
            acquireLease: false
        )
        let controller = IOSForegroundVoiceController(
            client: released.workflow.client,
            sceneRegistry: released.registry
        )
        await controller.activate()
        let command = try #require(controller.actionCommands.first {
            $0.action == .startStandard
        })
        released.releaseWorkflow()
        #expect(controller.submit(command, from: released.facade) == .accepted)
        try await waitUntil { controller.presentation.phase == .inactive }
        let postDeallocationLease = try #require(
            released.facade.acquireStartLease()
        )
        postDeallocationLease.finish()
    }



    @Test
    func unexpectedTailAndWatchdogErrorsResolveFailClosed() async throws {
        var settings = IOSAppSettings.defaults
        settings.voiceSessionPreferences.recordingStopTailDuration = .seconds2
        let tail = try await WorkflowFixture(
            settings: settings,
            permission: .granted,
            throwTailSleep: true
        )
        let tailToken = IOSForegroundVoiceWorkflowAttemptToken()
        let tailTask = Task { @MainActor in
            await tail.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: tail.lease
                ),
                token: tailToken,
                progress: { _ in }
            )
        }
        try await waitUntil { tail.events.contains("recording-start") }
        #expect(tail.workflow.finishUtterance(tailToken) == .accepted)
        _ = await tailTask.value
        #expect(tail.stopReasons == [.interrupted])

        let watchdog = try await WorkflowFixture(
            permission: .granted,
            throwMaximumSleep: true
        )
        let watchdogTask = Task { @MainActor in
            await watchdog.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: watchdog.lease
                ),
                token: IOSForegroundVoiceWorkflowAttemptToken(),
                progress: { _ in }
            )
        }
        _ = await watchdogTask.value
        #expect(watchdog.stopReasons == [.interrupted])
    }

    @Test
    func lateProviderSuccessAfterAggregateLossIsRejected() async throws {
        let record = try makeAcceptedDeliveryRecord()
        let fixture = try await WorkflowFixture(
            permission: .granted,
            completedCapture: true,
            processorSuspendsUntilCancelled: true,
            processorReturnsSuccessAfterCancellation: true,
            processorEmitsLateProgressAfterCancellation: true,
            processorResolution: .acceptance(.resultReady(record)),
            preacceptConsent: true
        )
        let token = IOSForegroundVoiceWorkflowAttemptToken()
        let task = Task { @MainActor in
            await fixture.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: fixture.lease
                ),
                token: token,
                progress: { _ in }
            )
        }
        try await waitUntil { fixture.events.contains("recording-start") }
        #expect(fixture.workflow.finishUtterance(token) == .accepted)
        try await waitUntil { fixture.events.contains("provider-process") }
        #expect(fixture.facade.updateActivity(.inactive) == .accepted)
        let resolution = await task.value
        #expect(resolution.outcome != .resultReady)
        #expect(resolution.observation.recovery == .pendingRetryOrDiscard)
    }

    @Test
    func pendingRetryPreservesTypedPreflightFailures() async throws {
        let credential = try await WorkflowFixture(
            permission: .granted,
            credentialResolutions: [.unavailable],
            preacceptConsent: true
        )
        _ = try await credential.seedPending()
        let credentialController = IOSForegroundVoiceController(
            client: credential.workflow.client,
            sceneRegistry: credential.registry
        )
        await credentialController.activate()
        let credentialRetry = try #require(
            credentialController.actionCommands.first {
                $0.action == .retryPending
            }
        )
        #expect(credentialController.submit(credentialRetry) == .accepted)
        try await waitUntil {
            credentialController.presentation.phase == .inactive
        }
        #expect(credentialController.presentation.failure == .unavailable)
        #expect(!credential.events.contains("provider-process"))

        let settings = try await WorkflowFixture(
            settingsLoads: [.failure],
            permission: .granted,
            preacceptConsent: true
        )
        _ = try await settings.seedPending()
        let settingsController = IOSForegroundVoiceController(
            client: settings.workflow.client,
            sceneRegistry: settings.registry
        )
        await settingsController.activate()
        let settingsRetry = try #require(
            settingsController.actionCommands.first {
                $0.action == .retryPending
            }
        )
        #expect(settingsController.submit(settingsRetry) == .accepted)
        try await waitUntil {
            settingsController.presentation.phase == .inactive
        }
        #expect(settingsController.presentation.failure == .localRecovery)
        #expect(!settings.events.contains("provider-process"))
    }

    @Test
    func ordinaryCancelHasNoFalseTooShortFailureOrRecovery() async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            acquireLease: false
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.workflow.client,
            sceneRegistry: fixture.registry
        )
        await controller.activate()
        let start = try #require(controller.actionCommands.first {
            $0.action == .startStandard
        })
        #expect(controller.submit(start, from: fixture.facade) == .accepted)
        try await waitUntil { controller.presentation.phase == .listening }
        let cancel = try #require(controller.actionCommands.first {
            $0.action == .cancelUtterance
        })
        #expect(controller.submit(cancel) == .accepted)
        try await waitUntil { controller.presentation.phase == .inactive }
        #expect(fixture.stopReasons == [.cancelled])
        #expect(controller.presentation.failure == nil)
        #expect(controller.presentation.outcome == nil)
        #expect(controller.presentation.recovery == .none)
        #expect(!fixture.events.contains("provider-process"))
    }

    @Test
    func cleanupHandlesReleasedOffMainHopToMainActorExactlyOnce()
        async throws {
        let counter = WorkflowCleanupCounter()

        var observation: IOSForegroundVoiceWorkflowObservation? =
            IOSForegroundVoiceWorkflowObservation {
                counter.increment()
            }
        let observationBox = WorkflowOffMainReleaseBox(observation)
        observation = nil

        var handoff: IOSForegroundVoiceWorkflowCaptureHandoff? =
            IOSForegroundVoiceWorkflowCaptureHandoff(
                prepare: { configuration in
                    try makePendingRecording(
                        outputIntent: .standard,
                        phase: .readyForTranscription,
                        configuration: configuration
                    )
                },
                release: { counter.increment() }
            )
        let handoffBox = WorkflowOffMainReleaseBox(handoff)
        handoff = nil

        var finalization: IOSForegroundVoiceWorkflowFinalizationLease? =
            IOSForegroundVoiceWorkflowFinalizationLease {
                counter.increment()
            }
        let finalizationBox = WorkflowOffMainReleaseBox(finalization)
        finalization = nil

        var audio: IOSForegroundVoiceWorkflowAudioLease? =
            IOSForegroundVoiceWorkflowAudioLease(
                freezeAndValidate: {},
                observe: { _ in
                    IOSForegroundVoiceWorkflowObservation(cancel: {})
                },
                deactivate: { counter.increment() }
            )
        let audioBox = WorkflowOffMainReleaseBox(audio)
        audio = nil

        await observationBox.releaseFromDetachedTask()
        await handoffBox.releaseFromDetachedTask()
        await finalizationBox.releaseFromDetachedTask()
        await audioBox.releaseFromDetachedTask()
        try await waitUntil { counter.value == 4 }

        await observationBox.releaseFromDetachedTask()
        await handoffBox.releaseFromDetachedTask()
        await finalizationBox.releaseFromDetachedTask()
        await audioBox.releaseFromDetachedTask()
        await Task.yield()
        #expect(counter.value == 4)
    }


    @Test
    func retryPendingLossDuringEveryAuthorityPreflightRemainsTerminal()
        async throws {
        for trigger in [
            WorkflowEventTrigger("settings-load"),
            WorkflowEventTrigger("consent-observe"),
            WorkflowEventTrigger("credential-resolve"),
            WorkflowEventTrigger("library-load", occurrence: 2),
            WorkflowEventTrigger("consent-revalidate", occurrence: 3),
            WorkflowEventTrigger("credential-revalidate", occurrence: 2),
        ] {
            let fixture = try await WorkflowFixture(
                permission: .granted,
                lossReactivationTrigger: trigger,
                preacceptConsent: true,
                acquireLease: false
            )
            _ = try await fixture.seedPending()
            let controller = IOSForegroundVoiceController(
                client: fixture.workflow.client,
                sceneRegistry: fixture.registry
            )
            await controller.activate()
            let retry = try #require(controller.actionCommands.first {
                $0.action == .retryPending
            })
            #expect(controller.submit(retry) == .accepted)
            try await waitUntil { controller.presentation.phase == .inactive }
            #expect(
                controller.presentation.recovery == .pendingRetryOrDiscard
            )
            #expect(!fixture.events.contains("provider-process"))
            #expect(fixture.registry.snapshot.isForegroundActive)
            if trigger.event == "settings-load" {
                #expect(!fixture.events.contains("library-load"))
            }
        }
    }

    @Test
    func parentCancelDuringRetryPreflightNeverDispatchesChild() async throws {
        for event in [
            "settings-load",
            "consent-observe",
            "credential-resolve",
        ] {
            let fixture = try await WorkflowFixture(
                permission: .granted,
                suspensionTrigger: WorkflowEventTrigger(event),
                preacceptConsent: true,
                acquireLease: false
            )
            _ = try await fixture.seedPending()
            let controller = IOSForegroundVoiceController(
                client: fixture.workflow.client,
                sceneRegistry: fixture.registry
            )
            await controller.activate()
            let retry = try #require(controller.actionCommands.first {
                $0.action == .retryPending
            })
            #expect(controller.submit(retry) == .accepted)
            try await waitUntil { fixture.events.contains(event) }
            let cancel = try #require(controller.actionCommands.first {
                $0.action == .cancelProcessing
            })
            #expect(controller.submit(cancel) == .accepted)
            try await waitUntil {
                fixture.events.contains("\(event)-cancelled")
            }
            try await waitUntil { controller.presentation.phase == .inactive }
            #expect(
                controller.presentation.recovery == .pendingRetryOrDiscard
            )
            #expect(!fixture.events.contains("provider-process"))
            if event == "settings-load" {
                #expect(!fixture.events.contains("library-load"))
            }
        }
    }

    @Test
    func retryPendingRejectsReplacedVisibleSourceAndPreflightMutations()
        async throws {
        let replaced = try await WorkflowFixture(
            permission: .granted,
            preacceptConsent: true,
            acquireLease: false
        )
        _ = try await replaced.seedPending()
        let replacedController = IOSForegroundVoiceController(
            client: replaced.workflow.client,
            sceneRegistry: replaced.registry
        )
        await replacedController.activate()
        let staleRetry = try #require(
            replacedController.actionCommands.first {
                $0.action == .retryPending
            }
        )
        _ = try replaced.replacePending()
        #expect(replacedController.submit(staleRetry) == .accepted)
        try await waitUntil {
            replacedController.presentation.phase == .inactive
        }
        #expect(!replaced.events.contains("provider-process"))

        for trigger in [
            WorkflowEventTrigger("settings-load"),
            WorkflowEventTrigger("consent-observe"),
            WorkflowEventTrigger("credential-resolve"),
            WorkflowEventTrigger("library-load", occurrence: 2),
            WorkflowEventTrigger("consent-revalidate", occurrence: 3),
            WorkflowEventTrigger("credential-revalidate", occurrence: 2),
        ] {
            let fixture = try await WorkflowFixture(
                permission: .granted,
                pendingMutationTrigger: trigger,
                preacceptConsent: true,
                acquireLease: false
            )
            _ = try await fixture.seedPending()
            let controller = IOSForegroundVoiceController(
                client: fixture.workflow.client,
                sceneRegistry: fixture.registry
            )
            await controller.activate()
            let retry = try #require(controller.actionCommands.first {
                $0.action == .retryPending
            })
            #expect(controller.submit(retry) == .accepted)
            try await waitUntil { controller.presentation.phase == .inactive }
            #expect(!fixture.events.contains("provider-process"))
        }
    }

    @Test
    func retryPendingRevalidatesFrozenConfigurationAndFinalProviderProofs()
        async throws {
        var changedSettings = IOSAppSettings.defaults
        changedSettings.localTextCleanupEnabled.toggle()
        var changedLibrary = IOSLibraryContent.defaults
        changedLibrary.replacementRules = [
            TextReplacementRule(search: "one", replacement: "two")
        ]
        let scenarios: [WorkflowFixture] = [
            try await WorkflowFixture(
                settingsLoads: [
                    .value(.defaults),
                    .value(changedSettings),
                ],
                permission: .granted,
                preacceptConsent: true,
                acquireLease: false
            ),
            try await WorkflowFixture(
                libraryLoads: [
                    .value(.defaults),
                    .value(changedLibrary),
                ],
                permission: .granted,
                preacceptConsent: true,
                acquireLease: false
            ),
            try await WorkflowFixture(
                permission: .granted,
                consentWithdrawalTrigger: WorkflowEventTrigger(
                    "library-load",
                    occurrence: 2
                ),
                preacceptConsent: true,
                acquireLease: false
            ),
            try await WorkflowFixture(
                permission: .granted,
                consentRevalidation: [true, false],
                preacceptConsent: true,
                acquireLease: false
            ),
            try await WorkflowFixture(
                permission: .granted,
                credentialRevalidation: [true, false],
                preacceptConsent: true,
                acquireLease: false
            ),
        ]
        for fixture in scenarios {
            _ = try await fixture.seedPending()
            let controller = IOSForegroundVoiceController(
                client: fixture.workflow.client,
                sceneRegistry: fixture.registry
            )
            await controller.activate()
            let retry = try #require(controller.actionCommands.first {
                $0.action == .retryPending
            })
            #expect(controller.submit(retry) == .accepted)
            try await waitUntil { controller.presentation.phase == .inactive }
            #expect(!fixture.events.contains("provider-process"))
            #expect(
                controller.presentation.recovery == .pendingRetryOrDiscard
            )
        }
    }

    @Test
    func ordinaryCancelPreservesDurableRecoveryActionAndFailure() async throws {
        let registry = IOSVoiceSceneRegistry()
        let facade = registry.registerScene(initialActivity: .active)
        let client = IOSForegroundVoiceClient(
            observe: {
                IOSForegroundVoiceObservation(
                    setup: .ready,
                    recovery: .none,
                    latestAvailability: .absent
                )
            },
            runStart: { _, lease, _, _ in
                do {
                    try await Task.sleep(for: .seconds(3_600))
                } catch {}
                _ = await MainActor.run { lease.finish() }
                return IOSForegroundVoiceResolution(
                    observation: IOSForegroundVoiceObservation(
                        setup: .ready,
                        recovery: .pendingRetryOrDiscard,
                        stage: .transcription,
                        latestAvailability: .absent
                    ),
                    stage: .transcription,
                    outcome: .recoverableFailure,
                    failure: .localRecovery
                )
            },
            run: { _, _, _ in
                IOSForegroundVoiceResolution(
                    observation: IOSForegroundVoiceObservation(
                        setup: .ready,
                        recovery: .none,
                        latestAvailability: .absent
                    )
                )
            },
            finishUtterance: { _ in .unavailable }
        )
        let controller = IOSForegroundVoiceController(
            client: client,
            sceneRegistry: registry
        )
        await controller.activate()
        let start = try #require(controller.actionCommands.first {
            $0.action == .startStandard
        })
        #expect(controller.submit(start, from: facade) == .accepted)
        let cancel = try #require(controller.actionCommands.first {
            $0.action == .cancelStart
        })
        #expect(controller.submit(cancel) == .accepted)
        try await waitUntil { controller.presentation.phase == .inactive }
        #expect(controller.presentation.outcome == nil)
        #expect(controller.presentation.failure == .localRecovery)
        #expect(controller.presentation.recovery == .pendingRetryOrDiscard)
        #expect(controller.actionCommands.contains { $0.action == .retryPending })
        #expect(controller.actionCommands.contains { $0.action == .discard })
    }

    @Test
    func recorderStartFailureAndPostStartInactiveAreInterruptedFailClosed()
        async throws {
        let failed = try await WorkflowFixture(
            permission: .granted,
            recordingStartResult: .failed,
            preacceptConsent: true
        )
        let inactive = try await WorkflowFixture(
            permission: .granted,
            recordingIsActive: false,
            preacceptConsent: true
        )
        for (fixture, expectedFailure) in [
            (failed, IOSForegroundVoiceFailure.operationFailed),
            (inactive, IOSForegroundVoiceFailure.tooShort),
        ] {
            let resolution = await fixture.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: fixture.lease
                ),
                token: IOSForegroundVoiceWorkflowAttemptToken(),
                progress: { _ in }
            )
            #expect(fixture.stopReasons == [.interrupted])
            #expect(resolution.outcome == .interrupted)
            #expect(resolution.failure == expectedFailure)
            #expect(!fixture.events.contains("provider-process"))
        }

        let cancelled = try await WorkflowFixture(
            permission: .granted,
            recordingStartResult: .cancelled,
            preacceptConsent: true
        )
        let cancellation = await cancelled.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: cancelled.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )
        #expect(cancelled.stopReasons == [.cancelled])
        #expect(cancellation.outcome == nil)
        #expect(cancellation.failure == nil)
    }

    @Test
    func passiveConfigurationFailureClearsStaleActivationProjection()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.translationConfiguration.targetLanguage = .english
        let fixture = try await WorkflowFixture(
            settings: settings,
            settingsLoads: [.value(settings), .failure],
            permission: .granted,
            acquireLease: false
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.workflow.client,
            sceneRegistry: fixture.registry
        )
        await controller.activate()
        #expect(controller.presentation.setup == .ready)
        #expect(controller.actionCommands.contains {
            $0.action == .startTranslation
        })
        await controller.activate()
        #expect(controller.presentation.setup == .unavailable)
        #expect(!controller.actionCommands.contains {
            $0.action == .startTranslation
        })

        var invalidSettings = settings
        invalidSettings.transcriptionConfiguration =
            TranscriptionConfiguration(
                language: .custom,
                customLanguageCode: "invalid!"
            )
        let invalid = try await WorkflowFixture(
            settingsLoads: [
                .value(settings),
                .value(invalidSettings),
            ],
            permission: .granted,
            acquireLease: false
        )
        let invalidController = IOSForegroundVoiceController(
            client: invalid.workflow.client,
            sceneRegistry: invalid.registry
        )
        await invalidController.activate()
        #expect(invalidController.actionCommands.contains {
            $0.action == .startTranslation
        })
        await invalidController.activate()
        #expect(
            invalidController.presentation.setup == .needsSetup(.transcription)
        )
        #expect(!invalidController.actionCommands.contains {
            $0.action == .startTranslation
        })
    }



    @Test
    func ordinaryWorkflowCancelPreservesActualCaptureRecoveryAction()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            preserveCaptureOnCancelledStop: true,
            preacceptConsent: true,
            acquireLease: false
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.workflow.client,
            sceneRegistry: fixture.registry
        )
        await controller.activate()
        let start = try #require(controller.actionCommands.first {
            $0.action == .startStandard
        })
        #expect(controller.submit(start, from: fixture.facade) == .accepted)
        try await waitUntil { controller.presentation.phase == .listening }
        let cancel = try #require(controller.actionCommands.first {
            $0.action == .cancelUtterance
        })
        #expect(controller.submit(cancel) == .accepted)
        try await waitUntil { controller.presentation.phase == .inactive }
        #expect(controller.presentation.outcome == nil)
        #expect(controller.presentation.failure == .localRecovery)
        #expect(controller.presentation.recovery == .captureDiscardOnly)
        #expect(controller.actionCommands.contains { $0.action == .discard })
        #expect(!controller.actionCommands.contains {
            $0.action == .retryPending
        })
    }

    @Test
    func cancellationDuringPendingPreparationCannotDispatchProvider()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            completedCapture: true,
            pendingPrepareSuspendsUntilCancelled: true,
            preacceptConsent: true
        )
        let token = IOSForegroundVoiceWorkflowAttemptToken()
        let task = Task { @MainActor in
            await fixture.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: fixture.lease
                ),
                token: token,
                progress: { _ in }
            )
        }
        try await waitUntil { fixture.events.contains("recording-start") }
        #expect(fixture.workflow.finishUtterance(token) == .accepted)
        try await waitUntil { fixture.events.contains("pending-prepare") }
        task.cancel()
        let resolution = await task.value
        #expect(fixture.events.contains("pending-prepare-cancelled"))
        #expect(!fixture.events.contains("provider-process"))
        #expect(resolution.observation.recovery == .pendingRetryOrDiscard)
        #expect(resolution.outcome != .resultReady)
    }

    @Test
    func initialProviderCancelReconcilesPendingOutsideCancelledTask()
        async throws {
        let record = try makeAcceptedDeliveryRecord()
        let fixture = try await WorkflowFixture(
            loadPendingFailsWhenCancelled: true,
            permission: .granted,
            completedCapture: true,
            processorSuspendsUntilCancelled: true,
            processorInitialProgress: .transcription,
            processorReturnsSuccessAfterCancellation: true,
            processorEmitsLateProgressAfterCancellation: true,
            processorResolution: .acceptance(.resultReady(record)),
            preacceptConsent: true,
            acquireLease: false
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.workflow.client,
            sceneRegistry: fixture.registry
        )
        await controller.activate()
        let start = try #require(controller.actionCommands.first {
            $0.action == .startStandard
        })
        #expect(controller.submit(start, from: fixture.facade) == .accepted)
        try await waitUntil { controller.presentation.phase == .listening }
        let finish = try #require(controller.actionCommands.first {
            $0.action == .finishUtterance
        })
        #expect(controller.submit(finish) == .accepted)
        try await waitUntil {
            controller.presentation.phase == .processing
                && controller.presentation.stage == .transcription
        }
        let cancel = try #require(controller.actionCommands.first {
            $0.action == .cancelProcessing
        })
        #expect(controller.submit(cancel) == .accepted)
        try await waitUntil {
            fixture.events.contains("provider-late-progress")
        }
        #expect(controller.presentation.phase == .processing)
        #expect(controller.presentation.stage == .transcription)
        try await waitUntil { controller.presentation.phase == .inactive }
        #expect(!fixture.events.contains("pending-load-cancelled"))
        #expect(controller.presentation.recovery == .pendingRetryOrDiscard)
        #expect(controller.presentation.outcome == .recoverableFailure)
        #expect(controller.presentation.failure == .localRecovery)
        #expect(controller.actionCommands.contains {
            $0.action == .retryPending
        })
        #expect(controller.actionCommands.contains { $0.action == .discard })
        #expect(controller.presentation.outcome != .resultReady)
    }

    @Test
    func workflowValuesRedactConfigurationAndPrivateAuthorities() async throws {
        let sentinel = "PRIVATE-PROMPT-9f42"
        var settings = IOSAppSettings.defaults
        settings.transcriptionConfiguration.freeformPrompt = sentinel
        let fixture = try await WorkflowFixture(
            settings: settings,
            permission: .granted
        )
        let configuration = IOSForegroundVoiceWorkflowConfiguration(
            settings: settings,
            library: .defaults
        )
        let start = IOSForegroundVoiceWorkflowStartRequest(
            outputIntent: .standard,
            sceneLease: fixture.lease
        )
        let values = [
            String(describing: fixture.workflow),
            String(reflecting: fixture.workflow),
            String(describing: configuration),
            String(reflecting: configuration),
            String(describing: start),
            String(reflecting: start),
            String(describing: IOSForegroundVoiceWorkflowCredentialProof()),
            String(reflecting: IOSForegroundVoiceWorkflowCredentialProof()),
        ]

        #expect(values.allSatisfy { !$0.contains(sentinel) })
        #expect(configuration.customMirror.children.isEmpty)
        #expect(start.customMirror.children.isEmpty)
    }

    @Test
    func keyboardRequestUsesSharedWorkflowAcrossBackgroundAndReturnsMatchingText()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            completedCapture: true,
            processorAcceptedText: "Keyboard pipeline result",
            preacceptConsent: true
        )
        var progress: [IOSKeyboardDictationWorkflowProgress] = []
        let requestID = UUID()
        let client = fixture.workflow.keyboardDictationClient
        let task = Task {
            await client.run(requestID) { progress.append($0) }
        }

        try await waitUntil {
            fixture.events.contains("recording-start")
        }
        _ = fixture.facade.updateActivity(.background)
        #expect(client.finish(requestID))

        #expect(await task.value == .accepted("Keyboard pipeline result"))
        #expect(progress.contains(.listening))
        #expect(progress.contains(.processing))
        #expect(fixture.events.count("recording-make") == 1)
        #expect(fixture.events.count("provider-process") == 1)
        #expect(fixture.permissionRequestCount == 0)
    }

    @Test
    func foregroundStartCannotCreateSecondRecorderDuringKeyboardRequest()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            preacceptConsent: true
        )
        let keyboardRequestID = UUID()
        let keyboardClient = fixture.workflow.keyboardDictationClient
        let keyboardTask = Task {
            await keyboardClient.run(keyboardRequestID) { _ in }
        }
        try await waitUntil {
            fixture.events.contains("recording-start")
        }

        let foreground = await fixture.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: fixture.lease
            ),
            token: IOSForegroundVoiceWorkflowAttemptToken(),
            progress: { _ in }
        )

        #expect(foreground.observation.recovery == .blocked)
        #expect(fixture.events.count("recording-make") == 1)
        #expect(keyboardClient.cancel(keyboardRequestID))
        #expect(await keyboardTask.value == .cancelled)
    }

    @Test
    func keyboardStartCannotCreateSecondRecorderDuringForegroundRequest()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            preacceptConsent: true
        )
        let foregroundToken = IOSForegroundVoiceWorkflowAttemptToken()
        let foregroundTask = Task {
            await fixture.workflow.start(
                IOSForegroundVoiceWorkflowStartRequest(
                    outputIntent: .standard,
                    sceneLease: fixture.lease
                ),
                token: foregroundToken,
                progress: { _ in }
            )
        }
        try await waitUntil {
            fixture.events.contains("recording-start")
        }

        let keyboard = await fixture.workflow.keyboardDictationClient.run(
            UUID()
        ) { _ in }

        #expect(keyboard == .failed)
        #expect(fixture.events.count("recording-make") == 1)
        #expect(fixture.workflow.finishUtterance(foregroundToken) == .accepted)
        _ = await foregroundTask.value
    }

    @Test
    func keyboardProviderTimeoutLeavesRecoverablePendingAndNoAcceptedText()
        async throws {
        let fixture = try await WorkflowFixture(
            permission: .granted,
            completedCapture: true,
            processorResolution: .notStarted(.timedOut),
            preacceptConsent: true
        )
        let requestID = UUID()
        let client = fixture.workflow.keyboardDictationClient
        let task = Task {
            await client.run(requestID) { _ in }
        }
        try await waitUntil {
            fixture.events.contains("recording-start")
        }
        #expect(client.finish(requestID))

        #expect(await task.value == .failed)
        #expect(fixture.events.count("provider-process") == 1)
        #expect(fixture.events.count("recording-make") == 1)
    }
}

private enum WorkflowCredentialResolution: Sendable {
    case available
    case needsSetup
    case unavailable
}

private struct WorkflowEventTrigger: Sendable {
    let event: String
    let occurrence: Int

    init(_ event: String, occurrence: Int = 1) {
        self.event = event
        self.occurrence = occurrence
    }
}

@MainActor
private final class WorkflowFixture {
    let events = WorkflowEventRecorder()
    let registry: IOSVoiceSceneRegistry
    let facade: IOSVoiceSceneFacade
    let lease: IOSVoiceSceneStartLease!
    let root: URL
    let persistenceOwner: IOSV1ForegroundVoicePersistenceOwner
    let consentCoordinator: IOSV1ProviderConsentCoordinator
    private let pendingBox: WorkflowPendingBox
    private(set) var workflow: IOSForegroundVoiceWorkflow!

    private(set) var stopReasons: [IOSForegroundVoiceWorkflowCaptureStopReason] = []
    private(set) var audioWasDeactivated = false
    private(set) var finalizationFinishCount = 0
    private(set) var permissionRequestCount = 0
    private(set) var terminalHandler: (@MainActor @Sendable (
        IOSForegroundVoiceWorkflowCaptureStopReason
    ) -> Void)?
    private(set) var audioEventHandler: (@MainActor @Sendable (
        IOSForegroundVoiceWorkflowAudioEvent
    ) -> Void)?
    private var finalizationExpirationHandler:
        (@MainActor @Sendable () -> Void)?
    private var permission: IOSMicrophonePermissionStatus

    init(
        settings: IOSAppSettings = .defaults,
        settingsLoads: [WorkflowLoad<IOSAppSettings>]? = nil,
        libraryLoads: [WorkflowLoad<IOSLibraryContent>] = [
            .value(.defaults)
        ],
        pendingLoads:
            [WorkflowLoad<IOSV1PendingRecordingObservation?>]? = nil,
        latestLoads:
            [WorkflowLoad<IOSV1ForegroundVoiceLatestResultObservation>]? = nil,
        loadPendingFailsWhenCancelled: Bool = false,
        permission: IOSMicrophonePermissionStatus,
        permissionOutcome:
            IOSForegroundVoiceWorkflowPermissionOutcome? = nil,
        reactivateSceneAfterPermission: Bool = true,
        consentContinuationAllowed: Bool = true,
        consentRevalidation: [Bool] = [true],
        credentialAvailable: Bool = true,
        credentialResolutions: [WorkflowCredentialResolution]? = nil,
        credentialRevalidation: [Bool] = [true],
        historyStops: Bool = true,
        deactivateSceneDuringHistoryStop: Bool = false,
        startBoundarySucceeds: Bool = true,
        deactivateSceneAtStartBoundary: Bool = false,
        audioFreezeResults: [Bool] = [true],
        recordingStartResult:
            IOSForegroundVoiceWorkflowRecordingStartResult = .started,
        recordingIsActive: Bool = true,
        recordingActiveValues: [Bool]? = nil,
        deactivateSceneDuringMakeRecording: Bool = false,
        terminalDuringRecordingStart:
            IOSForegroundVoiceWorkflowCaptureStopReason? = nil,
        completedCapture: Bool = false,
        preserveCaptureOnCancelledStop: Bool = false,
        preserveCaptureOnInterruptedStop: Bool = false,
        pendingPrepareSuspendsUntilCancelled: Bool = false,
        expireFinalizationImmediately: Bool = false,
        expireFinalizationAtStopBoundary: Bool = false,
        processorSuspendsUntilCancelled: Bool = false,
        processorInitialProgress: VoiceAttemptStage? = nil,
        processorReturnsSuccessAfterCancellation: Bool = false,
        processorEmitsLateProgressAfterCancellation: Bool = false,
        processorResolution: IOSForegroundVoiceProcessingResolution? = nil,
        processorAcceptedText: String? = nil,
        throwTailSleep: Bool = false,
        throwMaximumSleep: Bool = false,
        lossReactivationTrigger: WorkflowEventTrigger? = nil,
        pendingMutationTrigger: WorkflowEventTrigger? = nil,
        suspensionTrigger: WorkflowEventTrigger? = nil,
        consentWithdrawalTrigger: WorkflowEventTrigger? = nil,
        preacceptConsent: Bool = false,
        acquireLease: Bool = true,
        preRecoverHistory: Bool = true,
        useActualLifecycleRecovery: Bool = false,
        lifecycleRecoveryDisposition:
            IOSV1ContainingAppRecoveryDisposition = .complete,
        captureRecoveryObservations:
            [IOSV1ForegroundVoiceCaptureRecoveryObservation]? = nil
    ) async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        persistenceOwner = IOSV1ForegroundVoicePersistenceOwner(
            applicationSupportDirectoryURL: root
        )
        if preRecoverHistory {
            var lifecycleDisposition = await persistenceOwner
                .recoverContainingAppLifecycle(.processLaunch)
            for _ in 0..<12
            where lifecycleDisposition == .pendingLocalRecovery {
                lifecycleDisposition = await persistenceOwner
                    .recoverContainingAppLifecycle(.processLaunch)
            }
            guard lifecycleDisposition == .complete else {
                throw WorkflowFixtureError.unsupportedTestPath
            }
        }
        consentCoordinator = IOSV1ProviderConsentCoordinator(
            applicationSupportDirectoryURL: root
        )
        registry = IOSVoiceSceneRegistry()
        facade = registry.registerScene(initialActivity: .active)
        if acquireLease {
            guard let lease = facade.acquireStartLease() else {
                throw WorkflowFixtureError.missingSceneLease
            }
            self.lease = lease
        } else {
            lease = nil
        }
        self.permission = permission
        pendingBox = WorkflowPendingBox()
        if preacceptConsent {
            let observation = await consentCoordinator.observe()
            _ = try await consentCoordinator.accept(
                using: observation,
                decisionAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }

        let settingsSequence = WorkflowLoadSequence(
            settingsLoads ?? [.value(settings)]
        )
        let librarySequence = WorkflowLoadSequence(libraryLoads)
        let pendingLoadSequence = pendingLoads.map(WorkflowLoadSequence.init)
        let latestLoadSequence = latestLoads.map(WorkflowLoadSequence.init)
        let consentValidationSequence = WorkflowValueSequence(
            consentRevalidation
        )
        let credentialValidationSequence = WorkflowValueSequence(
            credentialRevalidation
        )
        let credentialResolutionSequence = WorkflowValueSequence(
            credentialResolutions ?? [
                credentialAvailable ? .available : .needsSetup
            ]
        )
        let audioFreezeSequence = WorkflowValueSequence(audioFreezeResults)
        let recordingActiveSequence = WorkflowValueSequence(
            recordingActiveValues ?? [recordingIsActive]
        )
        let captureRecoverySequence = captureRecoveryObservations.map(
            WorkflowValueSequence.init
        )
        let hook = WorkflowEventHook(
            lossReactivation: lossReactivationTrigger,
            pendingMutation: pendingMutationTrigger,
            suspension: suspensionTrigger,
            consentWithdrawal: consentWithdrawalTrigger
        )
        let replacementPending = try makePendingRecording(
            outputIntent: .translate,
            phase: .failed,
            configuration: .defaults
        )

        let events = events
        let owner = persistenceOwner
        let pendingBox = pendingBox
        let consent = consentCoordinator
        let registry = registry
        let sceneFacade = facade
        let applyHook: @Sendable (String) async -> Void = { event in
            let actions = hook.actions(for: event)
            if actions.mutatePending {
                pendingBox.store(replacementPending)
            }
            if actions.withdrawConsent {
                let observation = await consent.observe()
                _ = try? await consent.withdraw(
                    using: observation,
                    decisionAt: Date(timeIntervalSince1970: 1_800_000_002)
                )
            }
            if actions.loseAndReactivate {
                await MainActor.run {
                    _ = sceneFacade.updateActivity(.inactive)
                    _ = sceneFacade.updateActivity(.active)
                }
            }
            if actions.suspendUntilCancelled {
                do {
                    try await Task.sleep(for: .seconds(3_600))
                } catch {
                    events.record("\(event)-cancelled")
                }
            }
        }
        workflow = IOSForegroundVoiceWorkflow(
            dependencies: IOSForegroundVoiceWorkflowDependencies(
                sceneRegistry: registry,
                reconcileCaptureSources: {
                    events.record("capture-reconcile")
                    await applyHook("capture-reconcile")
                    if let captureRecoverySequence {
                        return captureRecoverySequence.next()
                    }
                    return await owner.reconcileCaptureSourcesAtLaunch()
                },
                recoverContainingAppLifecycle: { opportunity in
                    let name = switch opportunity {
                    case .processLaunch: "process-launch"
                    case .foregroundOpportunity: "foreground"
                    }
                    let event = "lifecycle-recover-\(name)"
                    events.record(event)
                    await applyHook(event)
                    if useActualLifecycleRecovery {
                        return await owner.recoverContainingAppLifecycle(
                            opportunity
                        )
                    }
                    return lifecycleRecoveryDisposition
                },
                loadPending: {
                    events.record("pending-load")
                    await applyHook("pending-load")
                    if loadPendingFailsWhenCancelled,
                       Task.isCancelled {
                        events.record("pending-load-cancelled")
                        throw CancellationError()
                    }
                    if let pendingLoadSequence {
                        return try pendingLoadSequence.next()
                    }
                    if let pending = pendingBox.load() {
                        return IOSV1PendingRecordingObservation(
                            recording: pending,
                            availability: .available
                        )
                    }
                    return try await owner.load()
                },
                loadLatest: {
                    events.record("latest-load")
                    if let latestLoadSequence {
                        return try latestLoadSequence.next()
                    }
                    return try await owner.loadLatestResult()
                },
                loadSettings: {
                    events.record("settings-load")
                    await applyHook("settings-load")
                    return try settingsSequence.next()
                },
                loadLibrary: {
                    events.record("library-load")
                    await applyHook("library-load")
                    return try librarySequence.next()
                },
                observeConsent: {
                    events.record("consent-observe")
                    await applyHook("consent-observe")
                    return await consent.observe()
                },
                continueConsent: { _, observation in
                    events.record("consent-continue")
                    guard consentContinuationAllowed else { return nil }
                    return try? await consent.accept(
                        using: observation,
                        decisionAt: Date(timeIntervalSince1970: 1_800_000_000)
                    )
                },
                revalidateConsent: { observation in
                    events.record("consent-revalidate")
                    await applyHook("consent-revalidate")
                    return consentValidationSequence.next()
                        && consent.makeAuthorization(
                        from: observation
                    ) != nil
                },
                resolveCredential: {
                    events.record("credential-resolve")
                    await applyHook("credential-resolve")
                    return switch credentialResolutionSequence.next() {
                    case .available:
                        .available(
                            IOSForegroundVoiceWorkflowCredentialProof()
                        )
                    case .needsSetup:
                        .needsSetup
                    case .unavailable:
                        .unavailable
                    }
                },
                revalidateCredential: { _ in
                    events.record("credential-revalidate")
                    await applyHook("credential-revalidate")
                    return credentialValidationSequence.next()
                },
                permission: IOSForegroundVoiceWorkflowPermissionClient(
                    read: { [weak self] in
                        events.record("permission-read")
                        return self?.permission ?? .unavailable
                    },
                    requestIfUndetermined: { [weak self] in
                        events.record("permission-request")
                        guard let self else { return .unavailable }
                        permissionRequestCount += 1
                        _ = facade.updateActivity(.inactive)
                        let outcome = permissionOutcome ?? .granted
                        if outcome == .granted {
                            self.permission = .granted
                        }
                        if reactivateSceneAfterPermission {
                            _ = facade.updateActivity(.active)
                        }
                        return outcome
                    }
                ),
                stopHistoryPlayback: {
                    events.record("history-stop")
                    if deactivateSceneDuringHistoryStop {
                        await MainActor.run {
                            _ = sceneFacade.updateActivity(.inactive)
                        }
                    }
                    return historyStops
                },
                activateAudio: { [weak self] in
                    events.record("audio-activate")
                    return IOSForegroundVoiceWorkflowAudioLease(
                        freezeAndValidate: {
                            events.record("input-freeze")
                            guard audioFreezeSequence.next() else {
                                throw WorkflowFixtureError.configuredFailure
                            }
                        },
                        observe: { [weak self] handler in
                            self?.audioEventHandler = handler
                            return IOSForegroundVoiceWorkflowObservation(
                                cancel: {}
                            )
                        },
                        deactivate: {
                            events.record("audio-deactivate")
                            self?.audioWasDeactivated = true
                        }
                    )
                },
                playStartBoundary: { [weak self] _ in
                    events.record("start-boundary")
                    if deactivateSceneAtStartBoundary {
                        _ = self?.facade.updateActivity(.inactive)
                    }
                    return startBoundarySucceeds
                },
                cancelStartBoundary: {
                    events.record("start-boundary-cancel")
                },
                playStopBoundary: { [weak self] _ in
                    events.record("stop-boundary")
                    if expireFinalizationAtStopBoundary {
                        self?.finalizationExpirationHandler?()
                    }
                },
                makeRecording: { [weak self] attemptID, _ in
                    events.record("recording-make")
                    if deactivateSceneDuringMakeRecording {
                        _ = self?.facade.updateActivity(.inactive)
                    }
                    return IOSForegroundVoiceWorkflowRecording(
                        start: { [weak self] in
                            events.record("recording-start")
                            if let terminalDuringRecordingStart {
                                self?.terminalHandler?(
                                    terminalDuringRecordingStart
                                )
                            }
                            return recordingStartResult
                        },
                        stop: { reason in
                            let name = switch reason {
                            case .done: "done"
                            case .cancelled: "cancelled"
                            case .interrupted: "interrupted"
                            case .maximumDuration: "maximum"
                            }
                            events.record("recording-stop-\(name)")
                            self?.stopReasons.append(reason)
                            if preserveCaptureOnCancelledStop,
                               reason == .cancelled {
                                let capture = try? await owner.createCapture(
                                    attemptID: UUID(),
                                    outputIntent: .standard
                                )
                                capture?.release()
                                return .preserved
                            }
                            if preserveCaptureOnInterruptedStop,
                               reason == .interrupted {
                                let capture = try? await owner.createCapture(
                                    attemptID: UUID(),
                                    outputIntent: .standard
                                )
                                capture?.release()
                                return .preserved
                            }
                            guard completedCapture else {
                                return reason == .cancelled
                                    ? .discarded
                                    : .invalid(.tooShort)
                            }
                            return .completed(
                                IOSForegroundVoiceWorkflowCaptureHandoff(
                                    prepare: { configuration in
                                        events.record("pending-prepare")
                                        if pendingPrepareSuspendsUntilCancelled {
                                            do {
                                                try await Task.sleep(
                                                    for: .seconds(3_600)
                                                )
                                            } catch {
                                                events.record(
                                                    "pending-prepare-cancelled"
                                                )
                                            }
                                        }
                                        let pending = try makePendingRecording(
                                            attemptID: attemptID,
                                            outputIntent: .standard,
                                            phase: .readyForTranscription,
                                            configuration: configuration
                                        )
                                        pendingBox.store(pending)
                                        return pending
                                    },
                                    release: {
                                        events.record("capture-release")
                                    }
                                )
                            )
                        },
                        isActive: { recordingActiveSequence.next() },
                        observeTerminal: { [weak self] handler in
                            self?.terminalHandler = handler
                            return IOSForegroundVoiceWorkflowObservation(
                                cancel: {}
                            )
                        }
                    )
                },
                beginFinalization: { [weak self] expiration in
                    events.record("finalization-begin")
                    self?.finalizationExpirationHandler = expiration
                    if expireFinalizationImmediately {
                        // Expiration is delivered synchronously to exercise
                        // the pre-close latch and no-provider guarantee.
                        // The real bridge may deliver at any later point.
                        expiration()
                    }
                    return IOSForegroundVoiceWorkflowFinalizationLease {
                        events.record("finalization-finish")
                        self?.finalizationFinishCount += 1
                    }
                },
                process: { request, progress in
                    events.record("provider-process")
                    if let processorInitialProgress {
                        await progress(processorInitialProgress)
                    }
                    if processorSuspendsUntilCancelled {
                        do {
                            try await Task.sleep(for: .seconds(3_600))
                        } catch {
                            if processorEmitsLateProgressAfterCancellation {
                                events.record("provider-late-progress")
                                await progress(.outputDelivery)
                                try? await Task.sleep(for: .milliseconds(250))
                            }
                            if processorReturnsSuccessAfterCancellation,
                               let processorResolution {
                                return processorResolution
                            }
                            return .notStarted(.cancelled)
                        }
                    }
                    if let processorAcceptedText {
                        let record = try! IOSV1AcceptedOutputDeliveryRecord(
                            resultID: UUID(),
                            sourceAttemptID:
                                request.pendingRecording.attemptID,
                            acceptedText: processorAcceptedText,
                            createdAt: Date(
                                timeIntervalSince1970: 1_800_000_000
                            )
                        )
                        return .acceptance(.resultReady(record))
                    }
                    return processorResolution
                        ?? .notStarted(.providerUnavailable)
                },
                recoverCapture: { attemptID, configuration in
                    events.record("capture-recover")
                    return try await owner.recoverCapture(
                        attemptID: attemptID,
                        transcriptionConfiguration: configuration
                    )
                },
                discardCapture: { attemptID in
                    events.record("capture-discard")
                    try await owner.discardCapture(attemptID: attemptID)
                },
                discardPending: { expectation in
                    events.record("pending-discard")
                    if pendingBox.remove(matching: expectation) {
                        return .discarded
                    }
                    return try await owner.discard(expected: expectation)
                },
                sleep: { duration in
                    if throwMaximumSleep,
                       duration >= .seconds(300) {
                        throw WorkflowFixtureError.configuredFailure
                    }
                    if throwTailSleep,
                       duration < .seconds(300) {
                        throw WorkflowFixtureError.configuredFailure
                    }
                    try await Task.sleep(for: duration)
                },
                makeUUID: { UUID() }
            )
        )
    }

    func emitTerminal(
        _ reason: IOSForegroundVoiceWorkflowCaptureStopReason
    ) {
        terminalHandler?(reason)
    }

    func emitAudio(_ event: IOSForegroundVoiceWorkflowAudioEvent) {
        audioEventHandler?(event)
    }

    func withdrawConsent() async throws {
        let observation = await consentCoordinator.observe()
        _ = try await consentCoordinator.withdraw(
            using: observation,
            decisionAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
    }

    func releaseWorkflow() {
        workflow = nil
    }

    func seedPending(
        outputIntent: DictationOutputIntent = .standard
    ) async throws -> IOSV1PendingRecording {
        let pending = try makePendingRecording(
            outputIntent: outputIntent,
            phase: .failed,
            configuration: .defaults
        )
        pendingBox.store(pending)
        return pending
    }

    @discardableResult
    func replacePending() throws -> IOSV1PendingRecording {
        let pending = try makePendingRecording(
            outputIntent: .translate,
            phase: .failed,
            configuration: .defaults
        )
        pendingBox.store(pending)
        return pending
    }
}


@MainActor
private func finishCompletedCapture(
    _ fixture: WorkflowFixture
) async throws -> IOSForegroundVoiceResolution {
    let token = IOSForegroundVoiceWorkflowAttemptToken()
    let task = Task { @MainActor in
        await fixture.workflow.start(
            IOSForegroundVoiceWorkflowStartRequest(
                outputIntent: .standard,
                sceneLease: fixture.lease
            ),
            token: token,
            progress: { _ in }
        )
    }
    try await waitUntil { fixture.events.contains("recording-start") }
    #expect(fixture.workflow.finishUtterance(token) == .accepted)
    return await task.value
}

private func makeAcceptedDeliveryRecord()
    throws -> IOSV1AcceptedOutputDeliveryRecord {
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    return try IOSV1AcceptedOutputDeliveryRecord(
        resultID: UUID(),
        sourceAttemptID: UUID(),
        acceptedText: "accepted",
        createdAt: createdAt
    )
}

@MainActor
private final class WorkflowCleanupCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

nonisolated private final class WorkflowOffMainReleaseBox:
    @unchecked Sendable {
    private let lock = NSLock()
    private var value: AnyObject?

    init(_ value: AnyObject?) {
        self.value = value
    }

    func releaseFromDetachedTask() async {
        await Task.detached { [self] in
            lock.withLock { value = nil }
        }.value
    }
}

private enum WorkflowLoad<Value: Sendable>: Sendable {
    case value(Value)
    case failure
}

private final class WorkflowLoadSequence<Value: Sendable>:
    @unchecked Sendable {
    private let lock = NSLock()
    private let values: [WorkflowLoad<Value>]
    private var index = 0

    init(_ values: [WorkflowLoad<Value>]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    func next() throws -> Value {
        try lock.withLock {
            let value = values[min(index, values.count - 1)]
            index += 1
            switch value {
            case .value(let result):
                return result
            case .failure:
                throw WorkflowFixtureError.configuredFailure
            }
        }
    }
}

private final class WorkflowValueSequence<Value: Sendable>:
    @unchecked Sendable {
    private let lock = NSLock()
    private let values: [Value]
    private var index = 0

    init(_ values: [Value]) {
        precondition(!values.isEmpty)
        self.values = values
    }

    func next() -> Value {
        lock.withLock {
            let value = values[min(index, values.count - 1)]
            index += 1
            return value
        }
    }
}

private struct WorkflowEventActions: Sendable {
    var loseAndReactivate = false
    var mutatePending = false
    var suspendUntilCancelled = false
    var withdrawConsent = false
}

private final class WorkflowEventHook: @unchecked Sendable {
    private let lock = NSLock()
    private var occurrences: [String: Int] = [:]
    private let lossReactivation: WorkflowEventTrigger?
    private let pendingMutation: WorkflowEventTrigger?
    private let suspension: WorkflowEventTrigger?
    private let consentWithdrawal: WorkflowEventTrigger?

    init(
        lossReactivation: WorkflowEventTrigger?,
        pendingMutation: WorkflowEventTrigger?,
        suspension: WorkflowEventTrigger?,
        consentWithdrawal: WorkflowEventTrigger?
    ) {
        self.lossReactivation = lossReactivation
        self.pendingMutation = pendingMutation
        self.suspension = suspension
        self.consentWithdrawal = consentWithdrawal
    }

    func actions(for event: String) -> WorkflowEventActions {
        lock.withLock {
            let occurrence = occurrences[event, default: 0] + 1
            occurrences[event] = occurrence
            return WorkflowEventActions(
                loseAndReactivate: matches(
                    lossReactivation,
                    event: event,
                    occurrence: occurrence
                ),
                mutatePending: matches(
                    pendingMutation,
                    event: event,
                    occurrence: occurrence
                ),
                suspendUntilCancelled: matches(
                    suspension,
                    event: event,
                    occurrence: occurrence
                ),
                withdrawConsent: matches(
                    consentWithdrawal,
                    event: event,
                    occurrence: occurrence
                )
            )
        }
    }

    private func matches(
        _ trigger: WorkflowEventTrigger?,
        event: String,
        occurrence: Int
    ) -> Bool {
        trigger?.event == event && trigger?.occurrence == occurrence
    }
}

private final class WorkflowPendingBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: IOSV1PendingRecording?

    func load() -> IOSV1PendingRecording? {
        lock.withLock { pending }
    }

    func store(_ pending: IOSV1PendingRecording) {
        lock.withLock { self.pending = pending }
    }

    func remove(
        matching expectation: IOSV1PendingRecordingExpectation
    ) -> Bool {
        lock.withLock {
            guard let pending,
                  IOSV1PendingRecordingExpectation(recording: pending)
                    == expectation else {
                return false
            }
            self.pending = nil
            return true
        }
    }
}

private func makePendingRecording(
    attemptID: UUID = UUID(),
    outputIntent: DictationOutputIntent,
    phase: IOSV1PendingRecordingPhase,
    configuration: TranscriptionConfiguration
) throws -> IOSV1PendingRecording {
    let transcriptionID: UUID? = switch phase {
    case .transcribing, .postProcessing, .outputDelivery:
        UUID()
    case .readyForTranscription, .failed, .acceptedCleanup:
        nil
    }
    return try IOSV1PendingRecording.qualificationFixture(
        attemptID: attemptID,
        outputIntent: outputIntent,
        phase: phase,
        transcriptionID: transcriptionID,
        transcriptionConfiguration: configuration
    )
}


private final class WorkflowEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func record(_ value: String) {
        lock.withLock { storage.append(value) }
    }

    func contains(_ value: String) -> Bool {
        lock.withLock { storage.contains(value) }
    }

    func count(_ value: String) -> Int {
        lock.withLock { storage.filter { $0 == value }.count }
    }
}

private func assertOrdered(
    _ expected: [String],
    in values: [String]
) {
    var previous = -1
    for value in expected {
        guard let index = values.indices.first(
            where: { $0 > previous && values[$0] == value }
        ) else {
            Issue.record("Missing ordered event: \(value); got: \(values)")
            return
        }
        previous = index
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if condition() { return }
        await Task.yield()
    }
    throw WorkflowFixtureError.timedOut
}

private enum WorkflowFixtureError: Error {
    case configuredFailure
    case missingSceneLease
    case unsupportedTestPath
    case timedOut
}
