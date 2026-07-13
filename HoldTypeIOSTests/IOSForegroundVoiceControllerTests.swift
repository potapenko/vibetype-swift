import HoldTypeDomain
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSForegroundVoiceControllerTests {
    @Test func constructionIsPassiveAndActivationIsCoalesced()
        async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation(),
            suspendNextObservation: true
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )

        #expect(controller.presentation == .initial)
        #expect(fixture.observeCallCount == 0)
        #expect(fixture.runOperations.isEmpty)

        let first = Task { await controller.activate() }
        try await voiceEventually {
            fixture.observeCallCount == 1
        }
        let second = Task { await controller.activate() }
        for _ in 0..<10 { await Task.yield() }

        #expect(fixture.observeCallCount == 1)
        #expect(controller.presentation.availableActions.isEmpty)

        fixture.resumeObservation()
        await first.value
        await second.value

        #expect(fixture.observeCallCount == 1)
        #expect(controller.presentation.phase == .inactive)
        #expect(
            controller.presentation.availableActions
                == [.startStandard]
        )
    }

    @Test func withdrawalCannotHideCommittedStartResult() async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation()
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )
        await controller.activate()
        let scene = controller.sceneRegistry.registerScene(
            initialActivity: .active
        )
        let start = try voiceCommand(.startStandard, in: controller)
        #expect(controller.submit(start, from: scene) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 1 }

        controller.providerConsentDidInvalidate()
        #expect(fixture.providerConsentInvalidationAuthorities.count == 1)
        #expect(fixture.cancellationAuthorities.isEmpty)
        fixture.resolveRun(
            at: 0,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation(
                    latest: .available
                ),
                outcome: .resultReady
            )
        )
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }

        #expect(controller.presentation.outcome == .resultReady)
        #expect(controller.presentation.latestAvailability == .available)
        #expect(controller.presentation.recovery == .none)
        #expect(fixture.cancellationAuthorities.isEmpty)
    }

    @Test func historySaveWarningKeepsResultAndNextStartAvailable()
        async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation()
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )
        await controller.activate()
        let scene = controller.sceneRegistry.registerScene(
            initialActivity: .active
        )
        let start = try voiceCommand(.startStandard, in: controller)
        #expect(controller.submit(start, from: scene) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 1 }

        fixture.resolveRun(
            at: 0,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation(latest: .available),
                outcome: .resultReady,
                warning: .historySaveFailed
            )
        )
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }

        #expect(controller.presentation.outcome == .resultReady)
        #expect(controller.presentation.warning == .historySaveFailed)
        #expect(controller.presentation.recovery == .none)
        #expect(controller.presentation.latestAvailability == .available)
        #expect(
            controller.presentation.availableActions == [.startStandard]
        )
        #expect(
            !controller.presentation.availableActions
                .contains(.retrySavingResult)
        )
    }

    @Test func withdrawalCannotHideCommittedRetryResult() async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation(
                recovery: .pendingRetryOrDiscard,
                stage: .transcription
            )
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )
        await controller.activate()
        let retry = try voiceCommand(.retryPending, in: controller)
        #expect(controller.submit(retry) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 1 }

        controller.providerConsentDidInvalidate()
        #expect(fixture.providerConsentInvalidationAuthorities.count == 1)
        #expect(fixture.cancellationAuthorities.isEmpty)
        fixture.resolveRun(
            at: 0,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation(
                    latest: .available
                ),
                outcome: .resultReady
            )
        )
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }

        #expect(controller.presentation.outcome == .resultReady)
        #expect(controller.presentation.latestAvailability == .available)
        #expect(controller.presentation.recovery == .none)
        #expect(fixture.cancellationAuthorities.isEmpty)
    }

    @Test func staleAndDuplicateStartCommandsAreRejected()
        async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation()
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )
        await controller.activate()
        let stale = try voiceCommand(.startStandard, in: controller)
        let scene = controller.sceneRegistry.registerScene(
            initialActivity: .active
        )

        await controller.activate()
        #expect(controller.submit(stale, from: scene) == .stale)
        #expect(scene.promptPresentation == .available)

        let current = try voiceCommand(.startStandard, in: controller)
        #expect(controller.submit(current, from: scene) == .accepted)
        #expect(scene.promptPresentation == .ownedByThisScene)
        #expect(controller.submit(current, from: scene) == .stale)
        #expect(scene.promptPresentation == .ownedByThisScene)
        try await voiceEventually { fixture.runOperations.count == 1 }
        #expect(fixture.runOperations == [.start(.standard)])

        fixture.resolveRun(
            at: 0,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation()
            )
        )
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }
        #expect(scene.promptPresentation == .available)
    }

    @Test func startRequiresAndForwardsTheExactSceneLease() async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation()
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )
        await controller.activate()
        let command = try voiceCommand(.startStandard, in: controller)

        #expect(controller.submit(command) == .unavailable)
        #expect(controller.presentation.phase == .inactive)
        #expect(fixture.runOperations.isEmpty)

        let scene = controller.sceneRegistry.registerScene(
            initialActivity: .active
        )
        #expect(controller.submit(command, from: scene) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 1 }
        #expect(fixture.runOperations == [.start(.standard)])
        let lease = try #require(fixture.startLeases.first)

        fixture.resolveRun(
            at: 0,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation()
            )
        )
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }
        #expect(!lease.finish())
        #expect(scene.promptPresentation == .available)
    }

    @Test func foreignOrInactiveSceneCannotAcquireTheProcessStartLease()
        async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation()
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )
        await controller.activate()
        let command = try voiceCommand(.startStandard, in: controller)
        let inactive = controller.sceneRegistry.registerScene(
            initialActivity: .inactive
        )
        let foreignRegistry = IOSVoiceSceneRegistry()
        let foreign = foreignRegistry.registerScene(initialActivity: .active)

        #expect(controller.submit(command, from: inactive) == .unavailable)
        #expect(controller.submit(command, from: foreign) == .unavailable)
        #expect(fixture.runOperations.isEmpty)
        #expect(inactive.promptPresentation == .unavailable)
        #expect(foreign.promptPresentation == .available)

        #expect(inactive.updateActivity(.active) == .accepted)
        #expect(controller.submit(command, from: inactive) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 1 }
        fixture.resolveRun(
            at: 0,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation()
            )
        )
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }
        #expect(inactive.promptPresentation == .available)
        #expect(foreign.promptPresentation == .available)
    }

    @Test func droppingControllerCancelsWorkAndRetiresAcceptedSceneLease()
        async throws {
        let fixture = IOSForegroundVoiceControllerDropFixture()
        var controller: IOSForegroundVoiceController? =
            IOSForegroundVoiceController(client: fixture.makeClient())
        let processRegistry = try #require(controller?.sceneRegistry)
        let scene = processRegistry.registerScene(
            initialActivity: .active
        )
        await controller?.activate()
        let command = try #require(
            controller?.actionCommands.first {
                $0.action == .startStandard
            }
        )
        #expect(controller?.submit(command, from: scene) == .accepted)
        try await voiceEventually { fixture.started }
        #expect(scene.promptPresentation == .ownedByThisScene)

        weak let releasedController = controller
        controller = nil

        try await voiceEventually {
            releasedController == nil && fixture.cancelled
        }
        #expect(scene.promptPresentation == .available)
        #expect(fixture.finishCount == 1)
        #expect(processRegistry.snapshot.registeredSceneCount == 1)
    }

    @Test func everyOperationClearsRecoveryAndRetryWaitsForProgress()
        async throws {
        let cases = [
            VoiceOperationCase(
                observation: voiceObservation(),
                action: .startStandard,
                operation: .start(.standard),
                phase: .arming,
                stage: nil,
                actions: [.cancelStart]
            ),
            VoiceOperationCase(
                observation: voiceObservation(
                    translationAvailable: true
                ),
                action: .startTranslation,
                operation: .start(.translate),
                phase: .arming,
                stage: nil,
                actions: [.cancelStart]
            ),
            VoiceOperationCase(
                observation: voiceObservation(
                    recovery: .captureRecoverOnly
                ),
                action: .recoverRecording,
                operation: .recoverRecording,
                phase: .finalizing,
                stage: .recordingFinalization,
                actions: []
            ),
            VoiceOperationCase(
                observation: voiceObservation(
                    recovery: .captureDiscardOnly
                ),
                action: .discard,
                operation: .discard,
                phase: .finalizing,
                stage: .recordingFinalization,
                actions: []
            ),
            VoiceOperationCase(
                observation: voiceObservation(
                    recovery: .pendingRetryOrDiscard
                ),
                action: .retryPending,
                operation: .retryPending,
                phase: .processing,
                stage: .transcription,
                actions: [.cancelProcessing]
            ),
            VoiceOperationCase(
                observation: voiceObservation(
                    recovery: .savingResult,
                    stage: .postProcessing
                ),
                action: .retrySavingResult,
                operation: .retrySavingResult,
                phase: .processing,
                stage: .postProcessing,
                actions: []
            ),
            VoiceOperationCase(
                observation: voiceObservation(
                    recovery: .localCheckpoint(.postProcessing)
                ),
                action: .retryLocalCheckpoint,
                operation: .retryLocalCheckpoint,
                phase: .processing,
                stage: .postProcessing,
                actions: [.cancelProcessing]
            ),
        ]

        for testCase in cases {
            let fixture = IOSForegroundVoiceClientFixture(
                observation: testCase.observation
            )
            let controller = IOSForegroundVoiceController(
                client: fixture.makeClient()
            )
            await controller.activate()

            let command = try voiceCommand(
                testCase.action,
                in: controller
            )
            #expect(submitVoiceCommand(command, in: controller) == .accepted)
            try await voiceEventually {
                fixture.runOperations.count == 1
            }

            #expect(fixture.runOperations == [testCase.operation])
            #expect(controller.presentation.phase == testCase.phase)
            #expect(controller.presentation.stage == testCase.stage)
            #expect(controller.presentation.recovery == .none)
            #expect(
                controller.presentation.availableActions
                    == testCase.actions
            )

            if let progress = testCase.proofProgress {
                fixture.sendProgress(progress, at: 0)
                #expect(
                    controller.presentation.availableActions
                        == [.cancelProcessing]
                )
            }

            fixture.resolveRun(
                at: 0,
                with: IOSForegroundVoiceResolution(
                    observation: voiceObservation()
                )
            )
            try await voiceEventually {
                controller.presentation.phase == .inactive
            }
        }
    }

    @Test func progressAndCompletionAreAuthorityChecked()
        async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation(
                latest: .priorAvailableWhileSaving
            )
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )
        await controller.activate()

        let firstStart = try voiceCommand(.startStandard, in: controller)
        #expect(submitVoiceCommand(firstStart, in: controller) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 1 }
        #expect(
            controller.presentation.latestAvailability
                == .priorAvailableWhileSaving
        )

        fixture.sendProgress(.listening, at: 0)
        #expect(controller.presentation.phase == .listening)
        #expect(controller.presentation.stage == nil)
        #expect(
            controller.presentation.availableActions
                == [.finishUtterance, .cancelUtterance]
        )

        fixture.sendProgress(.finalizing, at: 0)
        #expect(controller.presentation.phase == .finalizing)
        #expect(controller.presentation.stage == .recordingFinalization)
        #expect(controller.presentation.availableActions.isEmpty)

        fixture.sendProgress(.processing(.transcription), at: 0)
        #expect(controller.presentation.phase == .processing)
        #expect(controller.presentation.stage == .transcription)
        #expect(
            controller.presentation.availableActions
                == [.cancelProcessing]
        )
        #expect(
            controller.presentation.latestAvailability
                == .priorAvailableWhileSaving
        )

        fixture.sendProgress(.processing(.postProcessing), at: 0)
        #expect(controller.presentation.stage == .postProcessing)
        #expect(
            controller.presentation.availableActions
                == [.cancelProcessing]
        )

        fixture.sendProgress(.processing(.outputDelivery), at: 0)
        #expect(controller.presentation.stage == .outputDelivery)
        #expect(controller.presentation.availableActions.isEmpty)
        let outputDelivery = controller.presentation

        fixture.sendProgress(.listening, at: 0)
        fixture.sendProgress(.finalizing, at: 0)
        fixture.sendProgress(.processing(.transcription), at: 0)
        fixture.sendProgress(.processing(.postProcessing), at: 0)
        fixture.sendProgress(
            .processing(.recordingFinalization),
            at: 0
        )
        #expect(controller.presentation == outputDelivery)

        fixture.resolveRun(
            at: 0,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation(latest: .available),
                outcome: .resultReady
            )
        )
        try await voiceEventually {
            controller.presentation.outcome == .resultReady
        }
        let completed = controller.presentation

        fixture.sendProgress(.listening, at: 0)
        #expect(controller.presentation == completed)

        let secondStart = try voiceCommand(.startStandard, in: controller)
        #expect(submitVoiceCommand(secondStart, in: controller) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 2 }
        let secondArming = controller.presentation

        fixture.sendProgress(.processing(.postProcessing), at: 0)
        #expect(controller.presentation == secondArming)

        fixture.resolveRun(
            at: 1,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation(latest: .available)
            )
        )
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }
    }

    @Test func finishIsOneShotAndUnavailableCanBeRetried()
        async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation()
        )
        fixture.setFinishDisposition(.unavailable)
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )
        await controller.activate()
        let start = try voiceCommand(.startStandard, in: controller)
        #expect(submitVoiceCommand(start, in: controller) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 1 }
        fixture.sendProgress(.listening, at: 0)

        let unavailableFinish = try voiceCommand(
            .finishUtterance,
            in: controller
        )
        #expect(
            submitVoiceCommand(unavailableFinish, in: controller) == .accepted
        )
        #expect(fixture.finishAuthorities.count == 1)
        #expect(controller.presentation.phase == .listening)
        #expect(controller.presentation.failure == .operationFailed)
        #expect(
            controller.presentation.availableActions
                == [.finishUtterance, .cancelUtterance]
        )

        fixture.setFinishDisposition(.accepted)
        let acceptedFinish = try voiceCommand(
            .finishUtterance,
            in: controller
        )
        #expect(
            submitVoiceCommand(acceptedFinish, in: controller) == .accepted
        )
        #expect(submitVoiceCommand(acceptedFinish, in: controller) == .stale)
        #expect(fixture.finishAuthorities.count == 2)
        #expect(controller.presentation.phase == .listening)
        #expect(controller.presentation.failure == nil)
        #expect(
            controller.presentation.availableActions
                == [.cancelUtterance]
        )

        let cancel = try voiceCommand(.cancelUtterance, in: controller)
        #expect(submitVoiceCommand(cancel, in: controller) == .accepted)
        fixture.resolveRun(
            at: 0,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation(),
                outcome: .interrupted
            )
        )
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }
    }

    @Test func cancellationWaitsForDurableResolutionInEveryPhase()
        async throws {
        let scenarios = [
            VoiceCancellationCase(
                progress: nil,
                action: .cancelStart,
                phase: .arming,
                activeStage: nil,
                resolutionRecovery: .pendingRetryOrDiscard,
                terminalRecovery: .pendingRetryOrDiscard,
                terminalStage: .postProcessing,
                resolutionOutcome: .recoverableFailure,
                terminalOutcome: nil,
                terminalFailure: .operationFailed,
                terminalLatest: .available
            ),
            VoiceCancellationCase(
                progress: .listening,
                action: .cancelUtterance,
                phase: .listening,
                activeStage: nil,
                resolutionRecovery: .pendingRetryOrDiscard,
                terminalRecovery: .pendingRetryOrDiscard,
                terminalStage: .postProcessing,
                resolutionOutcome: .recoverableFailure,
                terminalOutcome: nil,
                terminalFailure: .operationFailed,
                terminalLatest: .available
            ),
            VoiceCancellationCase(
                progress: .processing(.transcription),
                action: .cancelProcessing,
                phase: .processing,
                activeStage: .transcription,
                resolutionRecovery: .pendingRetryOrDiscard,
                terminalRecovery: .pendingRetryOrDiscard,
                terminalStage: .postProcessing,
                resolutionOutcome: nil,
                terminalOutcome: .recoverableFailure,
                terminalFailure: .operationFailed,
                terminalLatest: .priorAvailableWhileSaving
            ),
            VoiceCancellationCase(
                progress: .processing(.postProcessing),
                action: .cancelProcessing,
                phase: .processing,
                activeStage: .postProcessing,
                resolutionRecovery: .savingResult,
                terminalRecovery: .savingResult,
                terminalStage: .postProcessing,
                resolutionOutcome: .recoverableFailure,
                terminalOutcome: nil,
                terminalFailure: .operationFailed,
                terminalLatest: .priorAvailableWhileSaving
            ),
        ]

        for scenario in scenarios {
            let fixture = IOSForegroundVoiceClientFixture(
                observation: voiceObservation(
                    latest: .priorAvailableWhileSaving
                )
            )
            let controller = IOSForegroundVoiceController(
                client: fixture.makeClient()
            )
            await controller.activate()
            let start = try voiceCommand(.startStandard, in: controller)
            #expect(submitVoiceCommand(start, in: controller) == .accepted)
            try await voiceEventually {
                fixture.runOperations.count == 1
            }
            if let progress = scenario.progress {
                fixture.sendProgress(progress, at: 0)
            }

            #expect(controller.presentation.phase == scenario.phase)
            #expect(
                controller.presentation.stage == scenario.activeStage
            )
            let cancel = try voiceCommand(scenario.action, in: controller)
            #expect(submitVoiceCommand(cancel, in: controller) == .accepted)
            let waitingForCleanup = controller.presentation

            #expect(waitingForCleanup.phase == scenario.phase)
            #expect(waitingForCleanup.availableActions.isEmpty)
            fixture.sendProgress(.processing(.postProcessing), at: 0)
            #expect(controller.presentation == waitingForCleanup)
            try await voiceEventually {
                fixture.cancellationAuthorities.count == 1
            }
            #expect(submitVoiceCommand(cancel, in: controller) == .stale)
            #expect(controller.presentation.phase == scenario.phase)

            fixture.resolveRun(
                at: 0,
                with: IOSForegroundVoiceResolution(
                    observation: voiceObservation(
                        recovery: scenario.resolutionRecovery,
                        stage: .postProcessing,
                        latest: .available
                    ),
                    stage: .postProcessing,
                    outcome: scenario.resolutionOutcome,
                    failure: .operationFailed
                )
            )
            try await voiceEventually {
                controller.presentation.phase == .inactive
            }

            #expect(
                controller.presentation.stage
                    == scenario.terminalStage
            )
            #expect(
                controller.presentation.outcome
                    == scenario.terminalOutcome
            )
            #expect(
                controller.presentation.failure
                    == scenario.terminalFailure
            )
            #expect(
                controller.presentation.recovery
                    == scenario.terminalRecovery
            )
            #expect(
                controller.presentation.latestAvailability
                    == scenario.terminalLatest
            )
            #expect(fixture.cancellationAuthorities.count == 1)
        }
    }

    @Test func cancelledScriptedSuccessCannotPublishNewResult()
        async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation(
                latest: .priorAvailableWhileSaving
            )
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )
        await controller.activate()
        let start = try voiceCommand(.startStandard, in: controller)
        #expect(submitVoiceCommand(start, in: controller) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 1 }
        let cancel = try voiceCommand(.cancelStart, in: controller)
        #expect(submitVoiceCommand(cancel, in: controller) == .accepted)

        fixture.resolveRun(
            at: 0,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation(latest: .available),
                stage: .outputDelivery,
                outcome: .resultReady
            )
        )
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }

        #expect(controller.presentation.outcome == nil)
        #expect(controller.presentation.failure == .localRecovery)
        #expect(controller.presentation.recovery == .blocked)
        #expect(controller.presentation.stage == nil)
        #expect(
            controller.presentation.latestAvailability
                == .priorAvailableWhileSaving
        )
        #expect(controller.presentation.availableActions.isEmpty)
    }

    @Test func terminalRecoveryRejectsHostileOutcomeCombinations()
        async throws {
        let cases = [
            VoiceTerminalCase(
                recovery: .pendingRetryOrDiscard,
                reportedStage: .postProcessing,
                inputOutcome: .resultReady,
                expectedStage: .postProcessing,
                expectedOutcome: .recoverableFailure,
                expectedActions: [.retryPending, .discard]
            ),
            VoiceTerminalCase(
                recovery: .savingResult,
                reportedStage: .postProcessing,
                inputOutcome: nil,
                expectedStage: .postProcessing,
                expectedOutcome: nil,
                expectedActions: [.retrySavingResult]
            ),
            VoiceTerminalCase(
                recovery: .localCheckpoint(.postProcessing),
                reportedStage: .transcription,
                inputOutcome: .resultReady,
                expectedStage: .postProcessing,
                expectedOutcome: .recoverableFailure,
                expectedActions: [.retryLocalCheckpoint]
            ),
            VoiceTerminalCase(
                recovery: .captureRecoverOrDiscard,
                reportedStage: .recordingFinalization,
                inputOutcome: .recoverableFailure,
                expectedStage: .recordingFinalization,
                expectedOutcome: nil,
                expectedActions: [.recoverRecording, .discard]
            ),
            VoiceTerminalCase(
                recovery: .blocked,
                reportedStage: .transcription,
                inputOutcome: .resultReady,
                expectedStage: nil,
                expectedOutcome: nil,
                expectedActions: []
            ),
            VoiceTerminalCase(
                recovery: .savingResult,
                reportedStage: .transcription,
                inputOutcome: .resultReady,
                expectedStage: .transcription,
                expectedOutcome: nil,
                expectedActions: [.retrySavingResult]
            ),
        ]

        for testCase in cases {
            let fixture = IOSForegroundVoiceClientFixture(
                observation: voiceObservation()
            )
            let controller = IOSForegroundVoiceController(
                client: fixture.makeClient()
            )
            await controller.activate()
            let start = try voiceCommand(.startStandard, in: controller)
            #expect(submitVoiceCommand(start, in: controller) == .accepted)
            try await voiceEventually {
                fixture.runOperations.count == 1
            }

            fixture.resolveRun(
                at: 0,
                with: IOSForegroundVoiceResolution(
                    observation: voiceObservation(
                        recovery: testCase.recovery
                    ),
                    stage: testCase.reportedStage,
                    outcome: testCase.inputOutcome,
                    failure: .operationFailed
                )
            )
            try await voiceEventually {
                controller.presentation.phase == .inactive
            }

            #expect(
                controller.presentation.stage
                    == testCase.expectedStage
            )
            #expect(
                controller.presentation.outcome
                    == testCase.expectedOutcome
            )
            #expect(controller.presentation.recovery == testCase.recovery)
            #expect(
                controller.presentation.availableActions
                    == testCase.expectedActions
            )
        }
    }

    @Test func recoverRecordingNeverAutomaticallyRetries()
        async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation(
                recovery: .captureRecoverOrDiscard
            )
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )
        await controller.activate()
        let recover = try voiceCommand(.recoverRecording, in: controller)
        #expect(submitVoiceCommand(recover, in: controller) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 1 }
        #expect(fixture.runOperations == [.recoverRecording])

        fixture.resolveRun(
            at: 0,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation(
                    recovery: .pendingRetryOrDiscard
                ),
                stage: .transcription,
                outcome: .recoverableFailure
            )
        )
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }
        for _ in 0..<10 { await Task.yield() }

        #expect(fixture.runOperations == [.recoverRecording])
        #expect(
            controller.presentation.availableActions
                == [.retryPending, .discard]
        )
    }

    @Test func observationsProduceExactPayloadFreeActionSets() async {
        let cases = [
            VoiceActionCase(
                observation: voiceObservation(),
                actions: [.startStandard],
                stage: nil
            ),
            VoiceActionCase(
                observation: voiceObservation(
                    translationAvailable: true
                ),
                actions: [.startStandard, .startTranslation],
                stage: nil
            ),
            VoiceActionCase(
                observation: voiceObservation(
                    recovery: .captureRecoverOrDiscard
                ),
                actions: [.recoverRecording, .discard],
                stage: nil
            ),
            VoiceActionCase(
                observation: voiceObservation(
                    recovery: .captureRecoverOnly
                ),
                actions: [.recoverRecording],
                stage: nil
            ),
            VoiceActionCase(
                observation: voiceObservation(
                    recovery: .captureDiscardOnly
                ),
                actions: [.discard],
                stage: nil
            ),
            VoiceActionCase(
                observation: voiceObservation(
                    recovery: .pendingRetryOrDiscard,
                    stage: .transcription
                ),
                actions: [.retryPending, .discard],
                stage: .transcription
            ),
            VoiceActionCase(
                observation: voiceObservation(
                    recovery: .savingResult,
                    stage: .postProcessing
                ),
                actions: [.retrySavingResult],
                stage: .postProcessing
            ),
            VoiceActionCase(
                observation: voiceObservation(
                    recovery: .localCheckpoint(.postProcessing)
                ),
                actions: [.retryLocalCheckpoint],
                stage: .postProcessing
            ),
            VoiceActionCase(
                observation: voiceObservation(recovery: .blocked),
                actions: [],
                stage: nil
            ),
            VoiceActionCase(
                observation: voiceObservation(
                    setup: .needsSetup(.openAI)
                ),
                actions: [],
                stage: nil
            ),
            VoiceActionCase(
                observation: voiceObservation(setup: .unavailable),
                actions: [],
                stage: nil
            ),
        ]

        for testCase in cases {
            let fixture = IOSForegroundVoiceClientFixture(
                observation: testCase.observation
            )
            let controller = IOSForegroundVoiceController(
                client: fixture.makeClient()
            )
            await controller.activate()

            #expect(
                controller.presentation.availableActions
                    == testCase.actions
            )
            #expect(controller.presentation.stage == testCase.stage)
            #expect(
                controller.presentation.outcome
                    == activationOutcome(
                        for: testCase.observation.recovery
                    )
            )
        }
    }

    @Test func resultReadyAndPriorLatestAvailabilityArePreserved()
        async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation(
                latest: .priorAvailableWhileSaving
            )
        )
        let controller = IOSForegroundVoiceController(
            client: fixture.makeClient()
        )
        await controller.activate()
        let start = try voiceCommand(.startStandard, in: controller)
        #expect(submitVoiceCommand(start, in: controller) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 1 }
        fixture.sendProgress(.processing(.postProcessing), at: 0)

        #expect(
            controller.presentation.latestAvailability
                == .priorAvailableWhileSaving
        )

        fixture.resolveRun(
            at: 0,
            with: IOSForegroundVoiceResolution(
                observation: voiceObservation(latest: .available),
                stage: .outputDelivery,
                outcome: .resultReady
            )
        )
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }

        #expect(controller.presentation.outcome == .resultReady)
        #expect(controller.presentation.stage == nil)
        #expect(
            controller.presentation.latestAvailability == .available
        )
    }

    @Test func diagnosticsAndReflectionAreAlwaysRedacted()
        async throws {
        let fixture = IOSForegroundVoiceClientFixture(
            observation: voiceObservation(
                setup: .needsSetup(.translation),
                recovery: .localCheckpoint(.postProcessing),
                latest: .cleanupPending,
                translationAvailable: true
            )
        )
        let client = fixture.makeClient()
        let controller = IOSForegroundVoiceController(client: client)
        await controller.activate()
        let command = try voiceCommand(
            .retryLocalCheckpoint,
            in: controller
        )
        #expect(submitVoiceCommand(command, in: controller) == .accepted)
        try await voiceEventually { fixture.runOperations.count == 1 }
        let authority = try #require(fixture.runAuthorities.first)
        let resolution = IOSForegroundVoiceResolution(
            observation: fixture.observation,
            stage: .postProcessing,
            outcome: .recoverableFailure,
            failure: .localRecovery
        )

        let values: [(Any, String)] = [
            (
                IOSForegroundVoiceSetup.needsSetup(.translation),
                "IOSForegroundVoiceSetup(<redacted>)"
            ),
            (
                IOSForegroundVoiceFailure.localRecovery,
                "IOSForegroundVoiceFailure(<redacted>)"
            ),
            (
                IOSForegroundVoiceWarning.historySaveFailed,
                "IOSForegroundVoiceWarning(<redacted>)"
            ),
            (
                IOSForegroundVoiceRecovery.localCheckpoint(
                    .postProcessing
                ),
                "IOSForegroundVoiceRecovery(<redacted>)"
            ),
            (
                IOSForegroundVoiceLatestAvailability.cleanupPending,
                "IOSForegroundVoiceLatestAvailability(<redacted>)"
            ),
            (
                IOSForegroundVoiceAction.retryLocalCheckpoint,
                "IOSForegroundVoiceAction(<redacted>)"
            ),
            (
                command,
                "IOSForegroundVoiceActionCommand(<redacted>)"
            ),
            (
                IOSForegroundVoiceActionAdmission.accepted,
                "IOSForegroundVoiceActionAdmission(<redacted>)"
            ),
            (
                controller.presentation,
                "IOSForegroundVoicePresentation(<redacted>)"
            ),
            (
                fixture.observation,
                "IOSForegroundVoiceObservation(<redacted>)"
            ),
            (
                IOSForegroundVoiceOperation.start(.translate),
                "IOSForegroundVoiceOperation(<redacted>)"
            ),
            (
                IOSForegroundVoiceProgress.processing(.postProcessing),
                "IOSForegroundVoiceProgress(<redacted>)"
            ),
            (
                resolution,
                "IOSForegroundVoiceResolution(<redacted>)"
            ),
            (
                authority,
                "IOSForegroundVoiceAuthority(<redacted>)"
            ),
            (
                IOSForegroundVoiceControlDisposition.unavailable,
                "IOSForegroundVoiceControlDisposition(<redacted>)"
            ),
            (
                client,
                "IOSForegroundVoiceClient(<redacted>)"
            ),
            (
                controller,
                "IOSForegroundVoiceController(<redacted>)"
            ),
        ]

        for (value, expected) in values {
            #expect(String(describing: value) == expected)
            #expect(String(reflecting: value) == expected)
            #expect(Mirror(reflecting: value).children.isEmpty)
        }

        fixture.resolveRun(at: 0, with: resolution)
        try await voiceEventually {
            controller.presentation.phase == .inactive
        }
    }
}

private struct VoiceOperationCase {
    let observation: IOSForegroundVoiceObservation
    let action: IOSForegroundVoiceAction
    let operation: IOSForegroundVoiceOperation
    let phase: VoiceWorkPhase
    let stage: VoiceAttemptStage?
    let actions: [IOSForegroundVoiceAction]
    var proofProgress: IOSForegroundVoiceProgress?

    init(
        observation: IOSForegroundVoiceObservation,
        action: IOSForegroundVoiceAction,
        operation: IOSForegroundVoiceOperation,
        phase: VoiceWorkPhase,
        stage: VoiceAttemptStage?,
        actions: [IOSForegroundVoiceAction],
        proofProgress: IOSForegroundVoiceProgress? = nil
    ) {
        self.observation = observation
        self.action = action
        self.operation = operation
        self.phase = phase
        self.stage = stage
        self.actions = actions
        self.proofProgress = proofProgress
    }
}

private struct VoiceCancellationCase {
    let progress: IOSForegroundVoiceProgress?
    let action: IOSForegroundVoiceAction
    let phase: VoiceWorkPhase
    let activeStage: VoiceAttemptStage?
    let resolutionRecovery: IOSForegroundVoiceRecovery
    let terminalRecovery: IOSForegroundVoiceRecovery
    let terminalStage: VoiceAttemptStage?
    let resolutionOutcome: VoiceAttemptOutcome?
    let terminalOutcome: VoiceAttemptOutcome?
    let terminalFailure: IOSForegroundVoiceFailure?
    let terminalLatest: IOSForegroundVoiceLatestAvailability
}

private struct VoiceTerminalCase {
    let recovery: IOSForegroundVoiceRecovery
    let reportedStage: VoiceAttemptStage
    let inputOutcome: VoiceAttemptOutcome?
    let expectedStage: VoiceAttemptStage?
    let expectedOutcome: VoiceAttemptOutcome?
    let expectedActions: [IOSForegroundVoiceAction]
}

private struct VoiceActionCase {
    let observation: IOSForegroundVoiceObservation
    let actions: [IOSForegroundVoiceAction]
    let stage: VoiceAttemptStage?
}

@MainActor
private final class IOSForegroundVoiceClientFixture {
    private(set) var observation: IOSForegroundVoiceObservation
    private(set) var observeCallCount = 0
    private(set) var runOperations: [IOSForegroundVoiceOperation] = []
    private(set) var runAuthorities: [IOSForegroundVoiceAuthority] = []
    private(set) var startLeases: [IOSVoiceSceneStartLease] = []
    private(set) var finishAuthorities: [IOSForegroundVoiceAuthority] = []
    private(set) var cancellationAuthorities:
        [IOSForegroundVoiceAuthority] = []
    private(set) var providerConsentInvalidationAuthorities:
        [IOSForegroundVoiceAuthority] = []

    private var suspendNextObservation: Bool
    private var observationContinuation:
        CheckedContinuation<IOSForegroundVoiceObservation, Never>?
    private var progressCallbacks: [IOSForegroundVoiceClient.Progress] = []
    private var runContinuations:
        [CheckedContinuation<IOSForegroundVoiceResolution, Never>?] = []
    private var finishDisposition:
        IOSForegroundVoiceControlDisposition = .accepted

    init(
        observation: IOSForegroundVoiceObservation,
        suspendNextObservation: Bool = false
    ) {
        self.observation = observation
        self.suspendNextObservation = suspendNextObservation
    }

    func makeClient() -> IOSForegroundVoiceClient {
        IOSForegroundVoiceClient(
            observe: { await self.observe() },
            runStart: { intent, lease, authority, progress in
                await self.runStart(
                    intent,
                    lease: lease,
                    authority: authority,
                    progress: progress
                )
            },
            run: { operation, authority, progress in
                await self.run(
                    operation,
                    authority: authority,
                    progress: progress
                )
            },
            finishUtterance: { authority in
                self.finish(authority)
            },
            providerConsentInvalidated: { authority in
                self.providerConsentInvalidationAuthorities.append(authority)
                return .unavailable
            }
        )
    }

    func setFinishDisposition(
        _ disposition: IOSForegroundVoiceControlDisposition
    ) {
        finishDisposition = disposition
    }

    func resumeObservation() {
        guard let continuation = observationContinuation else {
            Issue.record("Expected a suspended observation.")
            return
        }
        observationContinuation = nil
        continuation.resume(returning: observation)
    }

    func sendProgress(
        _ progress: IOSForegroundVoiceProgress,
        at index: Int
    ) {
        guard progressCallbacks.indices.contains(index) else {
            Issue.record("Expected a recorded progress callback.")
            return
        }
        progressCallbacks[index](progress)
    }

    func resolveRun(
        at index: Int,
        with resolution: IOSForegroundVoiceResolution
    ) {
        guard runContinuations.indices.contains(index),
              let continuation = runContinuations[index] else {
            Issue.record("Expected a suspended voice operation.")
            return
        }
        runContinuations[index] = nil
        continuation.resume(returning: resolution)
    }

    private func observe() async -> IOSForegroundVoiceObservation {
        observeCallCount += 1
        guard suspendNextObservation else { return observation }
        suspendNextObservation = false
        return await withCheckedContinuation { continuation in
            observationContinuation = continuation
        }
    }

    private func run(
        _ operation: IOSForegroundVoiceOperation,
        authority: IOSForegroundVoiceAuthority,
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        let index = runOperations.count
        runOperations.append(operation)
        runAuthorities.append(authority)
        progressCallbacks.append(progress)
        runContinuations.append(nil)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                runContinuations[index] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancellationAuthorities.append(authority)
            }
        }
    }

    private func runStart(
        _ intent: DictationOutputIntent,
        lease: IOSVoiceSceneStartLease,
        authority: IOSForegroundVoiceAuthority,
        progress: @escaping IOSForegroundVoiceClient.Progress
    ) async -> IOSForegroundVoiceResolution {
        startLeases.append(lease)
        let resolution = await run(
            .start(intent),
            authority: authority,
            progress: progress
        )
        _ = lease.finish()
        return resolution
    }

    private func finish(
        _ authority: IOSForegroundVoiceAuthority
    ) -> IOSForegroundVoiceControlDisposition {
        finishAuthorities.append(authority)
        return finishDisposition
    }
}

@MainActor
private final class IOSForegroundVoiceControllerDropFixture {
    private(set) var started = false
    private(set) var cancelled = false
    private(set) var finishCount = 0

    private var continuation:
        CheckedContinuation<Void, Never>?

    func makeClient() -> IOSForegroundVoiceClient {
        IOSForegroundVoiceClient(
            observe: {
                voiceObservation()
            },
            runStart: { _, lease, _, _ in
                await self.runStart(lease: lease)
            },
            run: { _, _, _ in
                IOSForegroundVoiceResolution(
                    observation: voiceObservation()
                )
            },
            finishUtterance: { _ in .unavailable }
        )
    }

    private func runStart(
        lease: IOSVoiceSceneStartLease
    ) async -> IOSForegroundVoiceResolution {
        started = true
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishCancelledStart(lease: lease)
            }
        }
        return IOSForegroundVoiceResolution(
            observation: voiceObservation()
        )
    }

    private func finishCancelledStart(lease: IOSVoiceSceneStartLease) {
        guard !cancelled else { return }
        cancelled = true
        if lease.finish() { finishCount += 1 }
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private func voiceObservation(
    setup: IOSForegroundVoiceSetup = .ready,
    recovery: IOSForegroundVoiceRecovery = .none,
    stage: VoiceAttemptStage? = nil,
    latest: IOSForegroundVoiceLatestAvailability = .absent,
    translationAvailable: Bool = false
) -> IOSForegroundVoiceObservation {
    IOSForegroundVoiceObservation(
        setup: setup,
        recovery: recovery,
        stage: stage,
        latestAvailability: latest,
        translationAvailable: translationAvailable
    )
}

private func activationOutcome(
    for recovery: IOSForegroundVoiceRecovery
) -> VoiceAttemptOutcome? {
    switch recovery {
    case .pendingRetryOrDiscard, .localCheckpoint:
        return .recoverableFailure
    case .none,
         .captureRecoverOrDiscard,
         .captureRecoverOnly,
         .captureDiscardOnly,
         .savingResult,
         .blocked:
        return nil
    }
}

@MainActor
private func voiceCommand(
    _ action: IOSForegroundVoiceAction,
    in controller: IOSForegroundVoiceController
) throws -> IOSForegroundVoiceActionCommand {
    try #require(
        controller.actionCommands.first { $0.action == action }
    )
}

@MainActor
private func submitVoiceCommand(
    _ command: IOSForegroundVoiceActionCommand,
    in controller: IOSForegroundVoiceController
) -> IOSForegroundVoiceActionAdmission {
    switch command.action {
    case .startStandard, .startTranslation:
        let scene = controller.sceneRegistry.registerScene(
            initialActivity: .active
        )
        return controller.submit(command, from: scene)
    case .cancelStart,
         .finishUtterance,
         .cancelUtterance,
         .cancelProcessing,
         .recoverRecording,
         .retryPending,
         .discard,
         .retrySavingResult,
         .retryLocalCheckpoint:
        return controller.submit(command)
    }
}

@MainActor
private func voiceEventually(
    _ predicate: @escaping @MainActor () -> Bool
) async throws {
    for _ in 0..<300 {
        if predicate() { return }
        await Task.yield()
    }
    throw IOSForegroundVoiceControllerTestTimeout()
}

private struct IOSForegroundVoiceControllerTestTimeout: Error {}
