import Foundation
import HoldTypeDomain
import HoldTypeOpenAI
@_spi(HoldTypeIOSCore) import HoldTypePersistence

protocol IOSForegroundVoicePersisting: Sendable {
    func load() async throws -> IOSPendingRecordingObservation?

    func beginTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID
    ) async throws -> IOSForegroundVoiceTranscriptionDispatch

    func retryTranscription(
        expected: IOSPendingRecordingCASExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSForegroundVoiceTranscriptionDispatch

    func markPostProcessing(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording

    func markOutputDelivery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording

    func markAwaitingRecovery(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording

    func recoverAfterProcessLoss(
        expected: IOSPendingRecordingCASExpectation
    ) async throws -> IOSPendingRecording

    func accept(
        _ preparation: IOSForegroundVoiceAcceptedOutputPreparation,
        expectedPending: IOSPendingRecordingCASExpectation
    ) async throws -> IOSForegroundVoiceAcceptanceResult

    func reconcileAcceptance(
        matching preparation: IOSForegroundVoiceAcceptedOutputPreparation
    ) async throws -> IOSForegroundVoiceAcceptanceResult?
}

extension IOSForegroundVoicePersistenceOwner:
    IOSForegroundVoicePersisting {}

/// One process-owned P4 provider and local-persistence orchestrator. It keeps
/// normalized provider output only in redacted process memory until the exact
/// Pending transition or P4B acceptance has durably taken ownership.
@_spi(HoldTypeIOSCore)
public actor IOSForegroundVoiceProcessor {
    typealias UsageRecorder = @Sendable (
        SuccessfulTranscriptionUsage
    ) async -> Void
    typealias ProviderRejectionRecorder = @Sendable (
        IOSOpenAICredentialGeneration
    ) async -> Void

    private let persistenceOwner: any IOSForegroundVoicePersisting
    private let consentCoordinator: IOSProviderConsentCoordinator
    private let stageExecutor: IOSProviderConsentStageExecutor
    private let provider: IOSForegroundVoiceOpenAIProviderOperations
    private let recordUsage: UsageRecorder
    private let recordProviderRejection: ProviderRejectionRecorder
    private let makeUUID: @Sendable () -> UUID
    private let postProcessor: TranscriptTextPostProcessor

    private var activeOperationID: UUID?
    private var activeProgressHandler:
        IOSForegroundVoiceProcessingProgressHandler?
    private var reportedProgressStages: [VoiceAttemptStage] = []
    private var retainedWork: IOSForegroundVoiceRetainedWork?

    public init(
        persistenceOwner: IOSForegroundVoicePersistenceOwner,
        consentCoordinator: IOSProviderConsentCoordinator,
        usageRepository: IOSTranscriptionUsageRepository,
        credentialCoordinator: IOSOpenAICredentialCoordinator
    ) {
        self.persistenceOwner = persistenceOwner
        self.consentCoordinator = consentCoordinator
        stageExecutor = IOSProviderConsentStageExecutor(
            consentCoordinator: consentCoordinator
        )
        provider = IOSForegroundVoiceOpenAIProviderOperations()
        recordUsage = { usage in
            _ = try? await usageRepository.record(usage)
        }
        recordProviderRejection = { generation in
            await credentialCoordinator.recordProviderRejection(
                for: generation
            )
        }
        makeUUID = { UUID() }
        postProcessor = TranscriptTextPostProcessor()
    }

    init(
        persistenceOwner: any IOSForegroundVoicePersisting,
        consentCoordinator: IOSProviderConsentCoordinator,
        provider: IOSForegroundVoiceOpenAIProviderOperations,
        recordUsage: @escaping UsageRecorder = { _ in },
        recordProviderRejection:
            @escaping ProviderRejectionRecorder = { _ in },
        makeUUID: @escaping @Sendable () -> UUID = { UUID() },
        postProcessor: TranscriptTextPostProcessor =
            TranscriptTextPostProcessor()
    ) {
        self.persistenceOwner = persistenceOwner
        self.consentCoordinator = consentCoordinator
        stageExecutor = IOSProviderConsentStageExecutor(
            consentCoordinator: consentCoordinator
        )
        self.provider = provider
        self.recordUsage = recordUsage
        self.recordProviderRejection = recordProviderRejection
        self.makeUUID = makeUUID
        self.postProcessor = postProcessor
    }

    public func process(
        _ request: IOSForegroundVoiceProcessingRequest,
        progress: @escaping IOSForegroundVoiceProcessingProgressHandler = {
            _ in
        }
    ) async -> IOSForegroundVoiceProcessingResolution {
        guard activeOperationID == nil else { return .busy }
        if let retainedWork {
            return .localRecoveryPending(
                failure: .localPersistence,
                stage: retainedWork.stage,
                disposition: retainedWork.recoveryDisposition
            )
        }
        guard let context = makeContext(from: request) else {
            return .notStarted(.invalidConfiguration)
        }
        guard consentCoordinator.makeAuthorization(
            from: context.consentObservation
        ) != nil else {
            return .notStarted(.providerConsentUnavailable)
        }

        let operationID = UUID()
        beginOperation(operationID, progress: progress)
        let work = IOSForegroundVoiceRetainedWork.beginning(context)
        retainedWork = work
        let resolution = await resume(work, operationID: operationID)
        finishOperation(operationID)
        return resolution
    }

    public func retryLocalRecovery(
        progress: @escaping IOSForegroundVoiceProcessingProgressHandler = {
            _ in
        }
    )
        async -> IOSForegroundVoiceProcessingResolution {
        guard activeOperationID == nil else { return .busy }
        guard let retainedWork else {
            return .notStarted(.localPersistence)
        }
        let operationID = UUID()
        beginOperation(operationID, progress: progress)
        if case .beginning = retainedWork {
            // Transcription begins only after Persistence returns the durable
            // one-shot dispatch below.
        } else {
            await reportProgress(
                retainedWork.stage,
                operationID: operationID
            )
        }
        let resolution = await resume(
            retainedWork,
            operationID: operationID
        )
        finishOperation(operationID)
        return resolution
    }

    public func hasLocalRecoveryPending() -> Bool {
        activeOperationID == nil && retainedWork != nil
    }

    private func resume(
        _ work: IOSForegroundVoiceRetainedWork,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        guard activeOperationID == operationID else { return .busy }
        switch work {
        case .beginning(let context):
            return await resumeBeginning(
                context,
                operationID: operationID
            )
        case .transcribing(let context, let recording):
            // A one-shot handoff cannot be reconstructed. Retire its exact
            // owner instead of replaying provider work.
            return await recover(
                context: context,
                recording: recording,
                failure: Task.isCancelled
                    ? .cancelled
                    : .localPersistence,
                stage: .transcription,
                operationID: operationID
            )
        case .transcriptionConsumed(
            let localContext,
            let recording,
            let transcript
        ):
            return await resumeTranscriptionConsumed(
                providerContext: nil,
                localContext: localContext,
                recording: recording,
                transcript: transcript,
                operationID: operationID
            )
        case .providerFreePostProcessing(
            let context,
            let recording,
            let transcript,
            let usageAttempted
        ):
            return await resumeProviderFreePostProcessing(
                context: context,
                recording: recording,
                transcript: transcript,
                usageAttempted: usageAttempted,
                operationID: operationID
            )
        case .postProcessing(
            let context,
            let recording,
            let transcript,
            let usageAttempted
        ):
            return await resumePostProcessing(
                context: context,
                recording: recording,
                transcript: transcript,
                usageAttempted: usageAttempted,
                operationID: operationID
            )
        case .finalText(let context, let recording, let text):
            return await resumeFinalText(
                context: context,
                recording: recording,
                text: text,
                operationID: operationID
            )
        case .outputDelivery(let context, let recording, let text):
            return await resumeOutputDelivery(
                context: context,
                recording: recording,
                text: text,
                operationID: operationID
            )
        case .recovering(
            let context,
            let recording,
            let failure,
            let stage
        ):
            return await resumeRecovery(
                context: context,
                recording: recording,
                failure: failure,
                stage: stage,
                operationID: operationID
            )
        }
    }

    private func resumeBeginning(
        _ context: IOSForegroundVoiceProviderContext,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        guard !Task.isCancelled else {
            retainedWork = nil
            return .notStarted(.cancelled)
        }
        retainedWork = .beginning(context)
        let dispatch: IOSForegroundVoiceTranscriptionDispatch
        do {
            switch context.mode {
            case .initial:
                dispatch = try await persistenceOwner.beginTranscription(
                    expected: IOSPendingRecordingCASExpectation(
                        recording: context.pendingRecording
                    ),
                    transcriptionID: context.transcriptionID
                )
            case .retry:
                dispatch = try await persistenceOwner.retryTranscription(
                    expected: IOSPendingRecordingCASExpectation(
                        recording: context.pendingRecording
                    ),
                    transcriptionID: context.transcriptionID,
                    transcriptionConfiguration:
                        context.transcriptionConfiguration
                )
            }
        } catch {
            return await reconcileBeginningFailure(
                context,
                operationID: operationID
            )
        }

        let recording = dispatch.recording
        retainedWork = .transcribing(context, recording)
        await reportProgress(.transcription, operationID: operationID)
        guard activeOperationID == operationID,
              !Task.isCancelled else {
            return await recover(
                context: context,
                recording: recording,
                failure: .cancelled,
                stage: .transcription,
                operationID: operationID
            )
        }
        guard let authorization = consentCoordinator.makeAuthorization(
            from: context.consentObservation
        ) else {
            return await recover(
                context: context,
                recording: recording,
                failure: .providerConsentUnavailable,
                stage: .transcription,
                operationID: operationID
            )
        }

        let executor = IOSForegroundVoiceTranscriptionExecutor(
            authorization: authorization,
            stageExecutor: stageExecutor,
            provider: provider,
            credential: context.credential.credential,
            promptComposition: context.promptComposition
        )
        do {
            let text = try await dispatch.execute(using: executor)
            guard let transcript = try? AcceptedTranscript(
                rawText: text
            ) else {
                return await recover(
                    context: context,
                    recording: recording,
                    failure: .invalidResponse,
                    stage: .transcription,
                    operationID: operationID
                )
            }
            let localContext = context.localTranscription
            await recordSuccessfulTranscriptionUsage(
                context: localContext.providerFree,
                recording: recording
            )
            let work = IOSForegroundVoiceRetainedWork
                .transcriptionConsumed(
                    localContext,
                    recording,
                transcript
            )
            retainedWork = work
            guard !Task.isCancelled else {
                return await recover(
                    context: localContext.providerFree,
                    recording: recording,
                    failure: .cancelled,
                    stage: .transcription,
                    operationID: operationID
                )
            }
            return await resumeTranscriptionConsumed(
                providerContext: context,
                localContext: localContext,
                recording: recording,
                transcript: transcript,
                operationID: operationID
            )
        } catch let error as IOSForegroundVoiceTranscriptionStageError {
            guard !Task.isCancelled else {
                return await recover(
                    context: context,
                    recording: recording,
                    failure: .cancelled,
                    stage: .transcription,
                    operationID: operationID
                )
            }
            switch error {
            case .failure(let failure):
                await recordCredentialRejectionIfNeeded(
                    failure,
                    context: context
                )
                return await recover(
                    context: context,
                    recording: recording,
                    failure: failure.publicFailure,
                    stage: .transcription,
                    operationID: operationID
                )
            case .cancelled:
                return await recover(
                    context: context,
                    recording: recording,
                    failure: .cancelled,
                    stage: .transcription,
                    operationID: operationID
                )
            case .authorizationUnavailable:
                return await recover(
                    context: context,
                    recording: recording,
                    failure: .providerConsentUnavailable,
                    stage: .transcription,
                    operationID: operationID
                )
            }
        } catch {
            let failure: IOSForegroundVoiceProcessingFailure =
                Task.isCancelled ? .cancelled : .invalidRecording
            return await recover(
                context: context,
                recording: recording,
                failure: failure,
                stage: .transcription,
                operationID: operationID
            )
        }
    }

    private func resumeTranscriptionConsumed(
        providerContext: IOSForegroundVoiceProviderContext?,
        localContext: IOSForegroundVoiceLocalTranscriptionContext,
        recording: IOSPendingRecording,
        transcript: AcceptedTranscript,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        let current = IOSForegroundVoiceRetainedWork.transcriptionConsumed(
            localContext,
            recording,
            transcript
        )
        retainedWork = current
        guard activeOperationID == operationID,
              !Task.isCancelled else {
            return await recover(
                context: localContext.providerFree,
                recording: recording,
                failure: .cancelled,
                stage: .transcription,
                operationID: operationID
            )
        }
        let postProcessing: IOSPendingRecording
        do {
            postProcessing = try await persistenceOwner.markPostProcessing(
                expected: IOSPendingRecordingCASExpectation(
                    recording: recording
                )
            )
        } catch {
            return await reconcilePostProcessingCommitFailure(
                source: recording,
                localContext: localContext,
                transcript: transcript,
                operationID: operationID,
                sourceWork: current
            )
        }
        await reportProgress(.postProcessing, operationID: operationID)
        guard activeOperationID == operationID,
              !Task.isCancelled else {
            return await recover(
                context: localContext.providerFree,
                recording: postProcessing,
                failure: .cancelled,
                stage: .postProcessing,
                operationID: operationID
            )
        }
        if let providerContext {
            let next = IOSForegroundVoiceRetainedWork.postProcessing(
                providerContext,
                postProcessing,
                transcript,
                usageAttempted: true
            )
            retainedWork = next
            return await resume(next, operationID: operationID)
        }
        let next = IOSForegroundVoiceRetainedWork
            .providerFreePostProcessing(
                localContext,
                postProcessing,
                transcript,
                usageAttempted: true
            )
        retainedWork = next
        return await resume(next, operationID: operationID)
    }

    private func resumeProviderFreePostProcessing(
        context: IOSForegroundVoiceLocalTranscriptionContext,
        recording: IOSPendingRecording,
        transcript: AcceptedTranscript,
        usageAttempted: Bool,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        guard activeOperationID == operationID,
              !Task.isCancelled else {
            return await recover(
                context: context.providerFree,
                recording: recording,
                failure: .cancelled,
                stage: .postProcessing,
                operationID: operationID
            )
        }
        if !usageAttempted {
            retainedWork = .providerFreePostProcessing(
                context,
                recording,
                transcript,
                usageAttempted: true
            )
            if let usage = try? SuccessfulTranscriptionUsage(
                transcriptionID: context.providerFree.transcriptionID,
                model: recording.transcriptionModel,
                audioDuration:
                    TimeInterval(recording.durationMilliseconds) / 1_000
            ) {
                await recordUsage(usage)
            }
        }
        guard !Task.isCancelled else {
            return await recover(
                context: context.providerFree,
                recording: recording,
                failure: .cancelled,
                stage: .postProcessing,
                operationID: operationID
            )
        }
        guard recording.outputIntent == .standard else {
            // A Translation stage cannot be resumed from retained text without
            // provider authority. Explicit Retry owns a fresh full chain.
            return await recover(
                context: context.providerFree,
                recording: recording,
                failure: .localPersistence,
                stage: .postProcessing,
                operationID: operationID
            )
        }
        let processedText = postProcessor.process(
            transcript.text,
            configuration: context.postProcessingConfiguration,
            fallback: transcript.text
        )
        guard let processed = try? AcceptedTranscript(
            rawText: processedText
        ) else {
            return await recover(
                context: context.providerFree,
                recording: recording,
                failure: .invalidConfiguration,
                stage: .postProcessing,
                operationID: operationID
            )
        }
        return await beginFinalText(
            processed,
            context: context.providerFree,
            recording: recording,
            operationID: operationID
        )
    }

    private func resumePostProcessing(
        context: IOSForegroundVoiceProviderContext,
        recording: IOSPendingRecording,
        transcript: AcceptedTranscript,
        usageAttempted: Bool,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        guard activeOperationID == operationID,
              !Task.isCancelled else {
            return await recover(
                context: context,
                recording: recording,
                failure: .cancelled,
                stage: .postProcessing,
                operationID: operationID
            )
        }
        var usageWasAttempted = usageAttempted
        if !usageWasAttempted {
            usageWasAttempted = true
            retainedWork = .postProcessing(
                context,
                recording,
                transcript,
                usageAttempted: true
            )
            if let usage = try? SuccessfulTranscriptionUsage(
                transcriptionID: context.transcriptionID,
                model: recording.transcriptionModel,
                audioDuration:
                    TimeInterval(recording.durationMilliseconds) / 1_000
            ) {
                await recordUsage(usage)
            }
        }
        guard !Task.isCancelled else {
            return await recover(
                context: context,
                recording: recording,
                failure: .cancelled,
                stage: .postProcessing,
                operationID: operationID
            )
        }

        let corrected = await correctedTranscript(
            transcript,
            context: context,
            recording: recording,
            operationID: operationID
        )
        switch corrected {
        case .recovery(let resolution):
            return resolution
        case .accepted(let correctedTranscript):
            guard !Task.isCancelled else {
                return await recover(
                    context: context,
                    recording: recording,
                    failure: .cancelled,
                    stage: .postProcessing,
                    operationID: operationID
                )
            }
            let processedText = postProcessor.process(
                correctedTranscript.text,
                configuration: context.postProcessingConfiguration,
                fallback: correctedTranscript.text
            )
            guard let processed = try? AcceptedTranscript(
                rawText: processedText
            ) else {
                return await recover(
                    context: context,
                    recording: recording,
                    failure: .invalidConfiguration,
                    stage: .postProcessing,
                    operationID: operationID
                )
            }
            return await finishPostProcessing(
                processed,
                context: context,
                recording: recording,
                operationID: operationID
            )
        }
    }

    private func correctedTranscript(
        _ transcript: AcceptedTranscript,
        context: IOSForegroundVoiceProviderContext,
        recording: IOSPendingRecording,
        operationID: UUID
    ) async -> IOSForegroundVoiceCorrectionResolution {
        guard context.correctionConfiguration.isEnabled,
              let authorization = consentCoordinator.makeAuthorization(
                  from: context.consentObservation
              ) else {
            return .accepted(transcript)
        }
        let provider = provider
        let credential = context.credential.credential
        let configuration = context.correctionConfiguration
        let outcome: IOSProviderConsentStageOutcome<
            AcceptedTranscript,
            IOSForegroundVoiceProviderFailure
        > = await stageExecutor.execute(
            authorization,
            for: .correction,
            operation: {
                let text = try await provider.correct(
                    transcript,
                    configuration,
                    credential
                )
                return try AcceptedTranscript(rawText: text)
            },
            normalizeFailure: {
                IOSForegroundVoiceProviderFailureMapper.correction($0)
            }
        )
        guard !Task.isCancelled else {
            return .recovery(
                await recover(
                    context: context,
                    recording: recording,
                    failure: .cancelled,
                    stage: .postProcessing,
                    operationID: operationID
                )
            )
        }
        switch outcome {
        case .success(let candidate):
            guard Self.isSafeCorrection(
                original: transcript.text,
                corrected: candidate.text
            ) else {
                return .accepted(transcript)
            }
            return .accepted(candidate)
        case .failure(let failure):
            await recordCredentialRejectionIfNeeded(
                failure,
                context: context
            )
            return .accepted(transcript)
        case .cancelled, .authorizationUnavailable:
            return .accepted(transcript)
        }
    }

    private func finishPostProcessing(
        _ processed: AcceptedTranscript,
        context: IOSForegroundVoiceProviderContext,
        recording: IOSPendingRecording,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        switch recording.outputIntent {
        case .standard:
            return await beginFinalText(
                processed,
                context: context,
                recording: recording,
                operationID: operationID
            )
        case .translate:
            guard let translation = context.translationConfiguration,
                  let authorization = consentCoordinator.makeAuthorization(
                      from: context.consentObservation
                  ) else {
                return await recover(
                    context: context,
                    recording: recording,
                    failure: context.translationConfiguration == nil
                        ? .invalidConfiguration
                        : .providerConsentUnavailable,
                    stage: .postProcessing,
                    operationID: operationID
                )
            }
            let provider = provider
            let credential = context.credential.credential
            let transcriptionConfiguration =
                context.transcriptionConfiguration
            let outcome: IOSProviderConsentStageOutcome<
                AcceptedTranscript,
                IOSForegroundVoiceProviderFailure
            > = await stageExecutor.execute(
                authorization,
                for: .translation,
                operation: {
                    let text = try await provider.translate(
                        TextTranslationRequest(
                            acceptedTranscript: processed,
                            translationConfiguration: translation,
                            transcriptionConfiguration:
                                transcriptionConfiguration
                        ),
                        credential
                    )
                    return try AcceptedTranscript(rawText: text)
                },
                normalizeFailure: {
                    IOSForegroundVoiceProviderFailureMapper.translation($0)
                }
            )
            guard !Task.isCancelled else {
                return await recover(
                    context: context,
                    recording: recording,
                    failure: .cancelled,
                    stage: .postProcessing,
                    operationID: operationID
                )
            }
            switch outcome {
            case .success(let translated):
                let final: AcceptedTranscript
                if context.postProcessingConfiguration
                    .localTextCleanupEnabled {
                    let normalized = TranscriptTextPostProcessor
                        .normalizedInformalTypography(
                            from: translated.text,
                            fallback: translated.text
                        )
                    guard let accepted = try? AcceptedTranscript(
                        rawText: normalized
                    ) else {
                        return await recover(
                            context: context,
                            recording: recording,
                            failure: .invalidResponse,
                            stage: .postProcessing,
                            operationID: operationID
                        )
                    }
                    final = accepted
                } else {
                    final = translated
                }
                return await beginFinalText(
                    final,
                    context: context,
                    recording: recording,
                    operationID: operationID
                )
            case .failure(let failure):
                await recordCredentialRejectionIfNeeded(
                    failure,
                    context: context
                )
                return await recover(
                    context: context,
                    recording: recording,
                    failure: failure.publicFailure,
                    stage: .postProcessing,
                    operationID: operationID
                )
            case .cancelled:
                return await recover(
                    context: context,
                    recording: recording,
                    failure: .cancelled,
                    stage: .postProcessing,
                    operationID: operationID
                )
            case .authorizationUnavailable:
                return await recover(
                    context: context,
                    recording: recording,
                    failure: .providerConsentUnavailable,
                    stage: .postProcessing,
                    operationID: operationID
                )
            }
        }
    }

    private func beginFinalText(
        _ text: AcceptedTranscript,
        context: IOSForegroundVoiceProviderContext,
        recording: IOSPendingRecording,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        await beginFinalText(
            text,
            context: context.providerFree,
            recording: recording,
            operationID: operationID
        )
    }

    private func beginFinalText(
        _ text: AcceptedTranscript,
        context providerFree: IOSForegroundVoiceProviderFreeContext,
        recording: IOSPendingRecording,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        guard !Task.isCancelled else {
            return await recover(
                context: providerFree,
                recording: recording,
                failure: .cancelled,
                stage: .postProcessing,
                operationID: operationID
            )
        }
        let work = IOSForegroundVoiceRetainedWork.finalText(
            providerFree,
            recording,
            text
        )
        retainedWork = work
        return await resume(work, operationID: operationID)
    }

    private func resumeFinalText(
        context: IOSForegroundVoiceProviderFreeContext,
        recording: IOSPendingRecording,
        text: AcceptedTranscript,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        let current = IOSForegroundVoiceRetainedWork.finalText(
            context,
            recording,
            text
        )
        retainedWork = current
        guard !Task.isCancelled else {
            return await recover(
                context: context,
                recording: recording,
                failure: .cancelled,
                stage: .postProcessing,
                operationID: operationID
            )
        }
        let outputDelivery: IOSPendingRecording
        do {
            outputDelivery = try await persistenceOwner.markOutputDelivery(
                expected: IOSPendingRecordingCASExpectation(
                    recording: recording
                )
            )
        } catch {
            return await reconcileOutputDeliveryCommitFailure(
                source: recording,
                context: context,
                text: text,
                operationID: operationID,
                sourceWork: current
            )
        }
        await reportProgress(.outputDelivery, operationID: operationID)
        let next = IOSForegroundVoiceRetainedWork.outputDelivery(
            context,
            outputDelivery,
            text
        )
        retainedWork = next
        guard activeOperationID == operationID,
              !Task.isCancelled else {
            return localRecovery(
                retaining: next,
                failure: .cancelled,
                stage: .outputDelivery
            )
        }
        return await resume(next, operationID: operationID)
    }

    private func resumeOutputDelivery(
        context: IOSForegroundVoiceProviderFreeContext,
        recording: IOSPendingRecording,
        text: AcceptedTranscript,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        let current = IOSForegroundVoiceRetainedWork.outputDelivery(
            context,
            recording,
            text
        )
        retainedWork = current
        guard activeOperationID == operationID,
              !Task.isCancelled else {
            return localRecovery(
                retaining: current,
                failure: .cancelled,
                stage: .outputDelivery
            )
        }
        let preparation: IOSForegroundVoiceAcceptedOutputPreparation
        do {
            preparation = try IOSForegroundVoiceAcceptedOutputPreparation(
                deliveryID: context.deliveryID,
                sessionID: context.sessionID,
                attemptID: recording.attemptID,
                transcriptID: context.transcriptionID,
                rawAcceptedText: text.text,
                outputIntent: context.outputIntent,
                keepLatestResult: context.keepLatestResult
            )
        } catch {
            return localRecovery(
                retaining: current,
                failure: .invalidConfiguration,
                stage: .outputDelivery
            )
        }
        do {
            let result = try await persistenceOwner.accept(
                preparation,
                expectedPending: IOSPendingRecordingCASExpectation(
                    recording: recording
                )
            )
            retainedWork = nil
            return .acceptance(result)
        } catch {
            return await reconcileAcceptanceFailure(
                preparation: preparation,
                source: recording,
                sourceWork: current
            )
        }
    }

    private func recover(
        context: IOSForegroundVoiceProviderContext,
        recording: IOSPendingRecording,
        failure: IOSForegroundVoiceProcessingFailure,
        stage: VoiceAttemptStage,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        await recover(
            context: context.providerFree,
            recording: recording,
            failure: failure,
            stage: stage,
            operationID: operationID
        )
    }

    private func recover(
        context: IOSForegroundVoiceProviderFreeContext,
        recording: IOSPendingRecording,
        failure: IOSForegroundVoiceProcessingFailure,
        stage: VoiceAttemptStage,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        let work = IOSForegroundVoiceRetainedWork.recovering(
            context,
            recording,
            failure,
            stage
        )
        retainedWork = work
        return await resume(work, operationID: operationID)
    }

    private func resumeRecovery(
        context: IOSForegroundVoiceProviderFreeContext,
        recording: IOSPendingRecording,
        failure: IOSForegroundVoiceProcessingFailure,
        stage: VoiceAttemptStage,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        let current = IOSForegroundVoiceRetainedWork.recovering(
            context,
            recording,
            failure,
            stage
        )
        retainedWork = current
        guard activeOperationID == operationID else { return .busy }
        let persistenceOwner = persistenceOwner
        let expectation = IOSPendingRecordingCASExpectation(
            recording: recording
        )
        let recoveryResult: Result<IOSPendingRecording, any Error>
        if Task.isCancelled {
            // Session cancellation has already retired provider authority. A
            // fresh local task must finish the exact durable recovery commit;
            // the cancelled session task itself cannot acquire Persistence.
            recoveryResult = await Task {
                try await persistenceOwner.markAwaitingRecovery(
                    expected: expectation
                )
            }.result
        } else {
            do {
                recoveryResult = .success(
                    try await persistenceOwner.markAwaitingRecovery(
                        expected: expectation
                    )
                )
            } catch {
                recoveryResult = .failure(error)
            }
        }
        switch recoveryResult {
        case .success(let recovered):
            retainedWork = nil
            return .awaitingRecovery(
                recovered,
                failure: failure,
                stage: stage
            )
        case .failure:
            return await reconcileRecoveryCommitFailure(
                context: context,
                source: recording,
                requestedFailure: failure,
                stage: stage,
                sourceWork: current
            )
        }
    }

    private func reconcileBeginningFailure(
        _ context: IOSForegroundVoiceProviderContext,
        operationID: UUID
    ) async -> IOSForegroundVoiceProcessingResolution {
        let sourceWork = IOSForegroundVoiceRetainedWork.beginning(context)
        let observation: IOSPendingRecordingObservation?
        do {
            observation = try await persistenceOwner.load()
        } catch {
            return localRecovery(
                retaining: sourceWork,
                failure: .localPersistence,
                stage: .transcription
            )
        }
        guard let current = observation?.recording else {
            return localRecovery(
                retaining: sourceWork,
                failure: Task.isCancelled ? .cancelled : .localPersistence,
                stage: .transcription
            )
        }
        if current == context.pendingRecording {
            return localRecovery(
                retaining: sourceWork,
                failure: .localPersistence,
                stage: .transcription
            )
        }
        guard Self.continuesAttempt(
            current,
            from: context.pendingRecording,
            model: context.transcriptionConfiguration.resolvedModel,
            languageCode:
                context.transcriptionConfiguration.resolvedLanguageCode
        ) else {
            retainedWork = nil
            return .notStarted(.localPersistence)
        }
        if current.phase == .awaitingRecovery,
           current.transcriptionID == nil {
            return await confirmAwaitingRecovery(
                current,
                context: context.providerFree,
                failure: .localPersistence,
                stage: .transcription
            )
        }
        guard current.phase == .transcribing,
              current.transcriptionID == context.transcriptionID else {
            retainedWork = nil
            return .notStarted(.localPersistence)
        }
        // A durable begin with no returned handoff has lost its one-shot
        // provider authority. Reconcile it to explicit Retry/Discard only.
        return await recover(
            context: context.providerFree,
            recording: current,
            failure: .localPersistence,
            stage: .transcription,
            operationID: operationID
        )
    }

    private func reconcilePostProcessingCommitFailure(
        source: IOSPendingRecording,
        localContext: IOSForegroundVoiceLocalTranscriptionContext,
        transcript: AcceptedTranscript,
        operationID: UUID,
        sourceWork: IOSForegroundVoiceRetainedWork
    ) async -> IOSForegroundVoiceProcessingResolution {
        let observation: IOSPendingRecordingObservation?
        do {
            observation = try await persistenceOwner.load()
        } catch {
            return localRecovery(
                retaining: sourceWork,
                failure: Task.isCancelled ? .cancelled : .localPersistence,
                stage: .transcription
            )
        }
        guard let current = observation?.recording else {
            return localRecovery(
                retaining: sourceWork,
                failure: Task.isCancelled ? .cancelled : .localPersistence,
                stage: .transcription
            )
        }
        if current == source {
            if Task.isCancelled {
                return await recover(
                    context: localContext.providerFree,
                    recording: current,
                    failure: .cancelled,
                    stage: .transcription,
                    operationID: operationID
                )
            }
            return localRecovery(
                retaining: sourceWork,
                failure: .localPersistence,
                stage: .transcription
            )
        }
        guard Self.continuesAttempt(current, from: source) else {
            return localRecovery(
                retaining: sourceWork,
                failure: Task.isCancelled ? .cancelled : .localPersistence,
                stage: .transcription
            )
        }
        if current.phase == .awaitingRecovery,
           current.transcriptionID == nil {
            return await confirmAwaitingRecovery(
                current,
                context: localContext.providerFree,
                failure: Task.isCancelled ? .cancelled : .localPersistence,
                stage: .transcription
            )
        }
        guard current.phase == .postProcessing,
              current.transcriptionID == source.transcriptionID else {
            return localRecovery(
                retaining: sourceWork,
                failure: Task.isCancelled ? .cancelled : .localPersistence,
                stage: .transcription
            )
        }
        let confirmationWork = IOSForegroundVoiceRetainedWork
            .transcriptionConsumed(
                localContext,
                current,
                transcript
            )
        let confirmedPostProcessing: IOSPendingRecording
        switch await confirmPostProcessing(current) {
        case .success(let confirmed):
            confirmedPostProcessing = confirmed
        case .failure:
            return localRecovery(
                retaining: confirmationWork,
                failure: .localPersistence,
                stage: .transcription
            )
        }
        await reportProgress(.postProcessing, operationID: operationID)
        guard activeOperationID == operationID,
              !Task.isCancelled else {
            return await recover(
                context: localContext.providerFree,
                recording: confirmedPostProcessing,
                failure: .cancelled,
                stage: .postProcessing,
                operationID: operationID
            )
        }
        let next = IOSForegroundVoiceRetainedWork
            .providerFreePostProcessing(
                localContext,
                confirmedPostProcessing,
                transcript,
                usageAttempted: true
            )
        retainedWork = next
        return await resume(next, operationID: operationID)
    }

    private func reconcileOutputDeliveryCommitFailure(
        source: IOSPendingRecording,
        context: IOSForegroundVoiceProviderFreeContext,
        text: AcceptedTranscript,
        operationID: UUID,
        sourceWork: IOSForegroundVoiceRetainedWork
    ) async -> IOSForegroundVoiceProcessingResolution {
        let observation: IOSPendingRecordingObservation?
        do {
            observation = try await persistenceOwner.load()
        } catch {
            return localRecovery(
                retaining: sourceWork,
                failure: Task.isCancelled ? .cancelled : .localPersistence,
                stage: .postProcessing
            )
        }
        guard let current = observation?.recording else {
            return localRecovery(
                retaining: sourceWork,
                failure: Task.isCancelled ? .cancelled : .localPersistence,
                stage: .postProcessing
            )
        }
        if current == source {
            if Task.isCancelled {
                return await recover(
                    context: context,
                    recording: current,
                    failure: .cancelled,
                    stage: .postProcessing,
                    operationID: operationID
                )
            }
            return localRecovery(
                retaining: sourceWork,
                failure: .localPersistence,
                stage: .postProcessing
            )
        }
        guard Self.continuesAttempt(current, from: source) else {
            return localRecovery(
                retaining: sourceWork,
                failure: Task.isCancelled ? .cancelled : .localPersistence,
                stage: .postProcessing
            )
        }
        if current.phase == .awaitingRecovery,
           current.transcriptionID == nil {
            return await confirmAwaitingRecovery(
                current,
                context: context,
                failure: Task.isCancelled ? .cancelled : .localPersistence,
                stage: .postProcessing
            )
        }
        guard current.phase == .outputDelivery,
              current.transcriptionID == source.transcriptionID else {
            return localRecovery(
                retaining: sourceWork,
                failure: Task.isCancelled ? .cancelled : .localPersistence,
                stage: .postProcessing
            )
        }
        let confirmationWork = IOSForegroundVoiceRetainedWork.finalText(
            context,
            current,
            text
        )
        let confirmedOutputDelivery: IOSPendingRecording
        switch await confirmOutputDelivery(current) {
        case .success(let confirmed):
            confirmedOutputDelivery = confirmed
        case .failure:
            return localRecovery(
                retaining: confirmationWork,
                failure: .localPersistence,
                stage: .postProcessing
            )
        }
        await reportProgress(.outputDelivery, operationID: operationID)
        let next = IOSForegroundVoiceRetainedWork.outputDelivery(
            context,
            confirmedOutputDelivery,
            text
        )
        retainedWork = next
        if activeOperationID != operationID || Task.isCancelled {
            return localRecovery(
                retaining: next,
                failure: .cancelled,
                stage: .outputDelivery
            )
        }
        return await resume(next, operationID: operationID)
    }

    private func reconcileRecoveryCommitFailure(
        context: IOSForegroundVoiceProviderFreeContext,
        source: IOSPendingRecording,
        requestedFailure: IOSForegroundVoiceProcessingFailure,
        stage: VoiceAttemptStage,
        sourceWork: IOSForegroundVoiceRetainedWork
    ) async -> IOSForegroundVoiceProcessingResolution {
        let observation: IOSPendingRecordingObservation?
        do {
            observation = try await persistenceOwner.load()
        } catch {
            return localRecovery(
                retaining: sourceWork,
                failure: .localPersistence,
                stage: stage
            )
        }
        guard let current = observation?.recording else {
            return localRecovery(
                retaining: sourceWork,
                failure: .localPersistence,
                stage: stage
            )
        }
        if Self.continuesAttempt(current, from: source),
           current.phase == .awaitingRecovery,
           current.transcriptionID == nil {
            return await confirmAwaitingRecovery(
                current,
                context: context,
                failure: requestedFailure,
                stage: stage
            )
        }
        guard current == source else {
            return localRecovery(
                retaining: sourceWork,
                failure: .localPersistence,
                stage: stage
            )
        }

        let persistenceOwner = persistenceOwner
        let expectation = IOSPendingRecordingCASExpectation(recording: current)
        let fallback = await Task {
            try await persistenceOwner.recoverAfterProcessLoss(
                expected: expectation
            )
        }.result
        if case .success(let recovered) = fallback {
            retainedWork = nil
            return .awaitingRecovery(
                recovered,
                failure: requestedFailure,
                stage: stage
            )
        }
        return localRecovery(
            retaining: sourceWork,
            failure: .localPersistence,
            stage: stage
        )
    }

    private func reconcileAcceptanceFailure(
        preparation: IOSForegroundVoiceAcceptedOutputPreparation,
        source _: IOSPendingRecording,
        sourceWork: IOSForegroundVoiceRetainedWork
    ) async -> IOSForegroundVoiceProcessingResolution {
        do {
            if let result = try await persistenceOwner.reconcileAcceptance(
                matching: preparation
            ) {
                retainedWork = nil
                return .acceptance(result)
            }
        } catch {}
        // Absence or a non-matching destination is ambiguous after a thrown
        // app-only acceptance. Preserve the provider-free text and retry only
        // this exact local checkpoint; never infer loss from a partial read.
        return localRecovery(
            retaining: sourceWork,
            failure: Task.isCancelled ? .cancelled : .localPersistence,
            stage: .outputDelivery
        )
    }

    private static func continuesAttempt(
        _ candidate: IOSPendingRecording,
        from source: IOSPendingRecording,
        model: String? = nil,
        languageCode: String?? = nil
    ) -> Bool {
        candidate.attemptID == source.attemptID
            && candidate.audioRelativeIdentifier
                == source.audioRelativeIdentifier
            && candidate.createdAt == source.createdAt
            && candidate.updatedAt >= source.updatedAt
            && candidate.outputIntent == source.outputIntent
            && candidate.transcriptionModel
                == (model ?? source.transcriptionModel)
            && candidate.transcriptionLanguageCode
                == (languageCode ?? source.transcriptionLanguageCode)
            && candidate.durationMilliseconds == source.durationMilliseconds
            && candidate.byteCount == source.byteCount
    }

    private func confirmPostProcessing(
        _ recording: IOSPendingRecording
    ) async -> Result<IOSPendingRecording, any Error> {
        let owner = persistenceOwner
        let expectation = IOSPendingRecordingCASExpectation(
            recording: recording
        )
        if Task.isCancelled {
            return await Task {
                try await owner.markPostProcessing(expected: expectation)
            }.result
        }
        do {
            return .success(
                try await owner.markPostProcessing(expected: expectation)
            )
        } catch {
            return .failure(error)
        }
    }

    private func confirmOutputDelivery(
        _ recording: IOSPendingRecording
    ) async -> Result<IOSPendingRecording, any Error> {
        let owner = persistenceOwner
        let expectation = IOSPendingRecordingCASExpectation(
            recording: recording
        )
        if Task.isCancelled {
            return await Task {
                try await owner.markOutputDelivery(expected: expectation)
            }.result
        }
        do {
            return .success(
                try await owner.markOutputDelivery(expected: expectation)
            )
        } catch {
            return .failure(error)
        }
    }

    private func confirmAwaitingRecovery(
        _ recording: IOSPendingRecording,
        context: IOSForegroundVoiceProviderFreeContext,
        failure: IOSForegroundVoiceProcessingFailure,
        stage: VoiceAttemptStage
    ) async -> IOSForegroundVoiceProcessingResolution {
        let work = IOSForegroundVoiceRetainedWork.recovering(
            context,
            recording,
            failure,
            stage
        )
        retainedWork = work
        let owner = persistenceOwner
        let expectation = IOSPendingRecordingCASExpectation(
            recording: recording
        )
        let result: Result<IOSPendingRecording, any Error>
        if Task.isCancelled {
            result = await Task {
                try await owner.markAwaitingRecovery(expected: expectation)
            }.result
        } else {
            do {
                result = .success(
                    try await owner.markAwaitingRecovery(
                        expected: expectation
                    )
                )
            } catch {
                result = .failure(error)
            }
        }
        switch result {
        case .success(let confirmed):
            retainedWork = nil
            return .awaitingRecovery(
                confirmed,
                failure: failure,
                stage: stage
            )
        case .failure:
            return localRecovery(
                retaining: work,
                failure: .localPersistence,
                stage: stage
            )
        }
    }

    private func localRecovery(
        retaining work: IOSForegroundVoiceRetainedWork,
        failure: IOSForegroundVoiceProcessingFailure,
        stage: VoiceAttemptStage
    ) -> IOSForegroundVoiceProcessingResolution {
        retainedWork = work
        return .localRecoveryPending(
            failure: failure,
            stage: stage,
            disposition: work.recoveryDisposition
        )
    }

    private func beginOperation(
        _ operationID: UUID,
        progress: @escaping IOSForegroundVoiceProcessingProgressHandler
    ) {
        activeOperationID = operationID
        activeProgressHandler = progress
        reportedProgressStages = []
    }

    private func finishOperation(_ operationID: UUID) {
        guard activeOperationID == operationID else { return }
        activeOperationID = nil
        activeProgressHandler = nil
        reportedProgressStages = []
    }

    private func reportProgress(
        _ stage: VoiceAttemptStage,
        operationID: UUID
    ) async {
        guard activeOperationID == operationID,
              !reportedProgressStages.contains(stage) else { return }
        reportedProgressStages.append(stage)
        guard let activeProgressHandler else { return }
        await activeProgressHandler(stage)
    }

    private func makeContext(
        from request: IOSForegroundVoiceProcessingRequest
    ) -> IOSForegroundVoiceProviderContext? {
        let pending = request.pendingRecording
        switch request.mode {
        case .initial:
            guard pending.phase == .readyForTranscription,
                  pending.transcriptionID == nil else { return nil }
        case .retry:
            guard (pending.phase == .readyForTranscription
                    || pending.phase == .awaitingRecovery),
                  pending.transcriptionID == nil else { return nil }
        }
        let transcription = request.settings.transcriptionConfiguration
        guard !transcription.customLanguageCodeValidation.isInvalid else {
            return nil
        }
        if request.mode == .initial {
            guard pending.transcriptionModel == transcription.resolvedModel,
                  pending.transcriptionLanguageCode
                    == transcription.resolvedLanguageCode else {
                return nil
            }
        }

        let translation: TranslationConfiguration?
        switch pending.outputIntent {
        case .standard:
            translation = nil
        case .translate:
            guard request.settings.translationConfiguration.canRunAction else {
                return nil
            }
            translation = request.settings.translationConfiguration
        }
        let prompt = TranscriptionPromptComposition(
            resolvedFreeformPrompt: transcription.resolvedFreeformPrompt,
            context: nil,
            emojiCommandsConfiguration:
                request.library.emojiCommandsConfiguration,
            customDictionary: request.library.customDictionary
        )
        let postProcessing = TranscriptPostProcessingConfiguration(
            localTextCleanupEnabled:
                request.settings.localTextCleanupEnabled,
            emojiCommands:
                request.library.emojiCommandsConfiguration,
            textReplacementRules: request.library.replacementRules
        )
        return IOSForegroundVoiceProviderContext(
            sessionID: request.sessionID,
            pendingRecording: pending,
            mode: request.mode,
            transcriptionConfiguration: transcription,
            correctionConfiguration:
                request.settings.textCorrectionConfiguration,
            translationConfiguration: translation,
            postProcessingConfiguration: postProcessing,
            promptComposition: prompt,
            keepLatestResult: request.settings.keepLatestResult,
            credential: request.credential,
            consentObservation: request.consentObservation,
            transcriptionID: makeUUID(),
            deliveryID: makeUUID()
        )
    }

    private func recordCredentialRejectionIfNeeded(
        _ failure: IOSForegroundVoiceProviderFailure,
        context: IOSForegroundVoiceProviderContext
    ) async {
        guard failure == .credentialRejected else { return }
        await recordProviderRejection(context.credential.generation)
    }

    private func recordSuccessfulTranscriptionUsage(
        context: IOSForegroundVoiceProviderFreeContext,
        recording: IOSPendingRecording
    ) async {
        guard let usage = try? SuccessfulTranscriptionUsage(
            transcriptionID: context.transcriptionID,
            model: recording.transcriptionModel,
            audioDuration:
                TimeInterval(recording.durationMilliseconds) / 1_000
        ) else { return }
        let recorder = recordUsage
        // A consumed provider success remains billable bookkeeping even when
        // the caller cancels immediately afterward. Keep this local, non-fatal
        // handoff outside the cancelled provider task.
        await Task { await recorder(usage) }.value
    }

    private static func isSafeCorrection(
        original: String,
        corrected: String
    ) -> Bool {
        guard let normalized = AcceptedTranscript.nonEmptyNormalizedText(
            from: corrected
        ) else {
            return false
        }
        guard original.count >= 20 else { return true }
        return normalized.count >= max(1, original.count / 3)
            && normalized.count <= original.count * 3
    }
}

private struct IOSForegroundVoiceProviderContext: Sendable {
    let sessionID: UUID
    let pendingRecording: IOSPendingRecording
    let mode: IOSForegroundVoiceProcessingMode
    let transcriptionConfiguration: TranscriptionConfiguration
    let correctionConfiguration: TextCorrectionConfiguration
    let translationConfiguration: TranslationConfiguration?
    let postProcessingConfiguration:
        TranscriptPostProcessingConfiguration
    let promptComposition: TranscriptionPromptComposition
    let keepLatestResult: Bool
    let credential: IOSResolvedOpenAICredential
    let consentObservation: IOSProviderConsentObservation
    let transcriptionID: UUID
    let deliveryID: UUID

    var providerFree: IOSForegroundVoiceProviderFreeContext {
        IOSForegroundVoiceProviderFreeContext(
            sessionID: sessionID,
            transcriptionID: transcriptionID,
            deliveryID: deliveryID,
            outputIntent: pendingRecording.outputIntent,
            keepLatestResult: keepLatestResult
        )
    }

    var localTranscription: IOSForegroundVoiceLocalTranscriptionContext {
        IOSForegroundVoiceLocalTranscriptionContext(
            providerFree: providerFree,
            postProcessingConfiguration: postProcessingConfiguration
        )
    }
}

private struct IOSForegroundVoiceLocalTranscriptionContext: Sendable {
    let providerFree: IOSForegroundVoiceProviderFreeContext
    let postProcessingConfiguration:
        TranscriptPostProcessingConfiguration
}

private struct IOSForegroundVoiceProviderFreeContext: Sendable {
    let sessionID: UUID
    let transcriptionID: UUID
    let deliveryID: UUID
    let outputIntent: DictationOutputIntent
    let keepLatestResult: Bool
}

private enum IOSForegroundVoiceRetainedWork: Sendable {
    case beginning(IOSForegroundVoiceProviderContext)
    case transcribing(
        IOSForegroundVoiceProviderContext,
        IOSPendingRecording
    )
    case transcriptionConsumed(
        IOSForegroundVoiceLocalTranscriptionContext,
        IOSPendingRecording,
        AcceptedTranscript
    )
    case providerFreePostProcessing(
        IOSForegroundVoiceLocalTranscriptionContext,
        IOSPendingRecording,
        AcceptedTranscript,
        usageAttempted: Bool
    )
    case postProcessing(
        IOSForegroundVoiceProviderContext,
        IOSPendingRecording,
        AcceptedTranscript,
        usageAttempted: Bool
    )
    case finalText(
        IOSForegroundVoiceProviderFreeContext,
        IOSPendingRecording,
        AcceptedTranscript
    )
    case outputDelivery(
        IOSForegroundVoiceProviderFreeContext,
        IOSPendingRecording,
        AcceptedTranscript
    )
    case recovering(
        IOSForegroundVoiceProviderFreeContext,
        IOSPendingRecording,
        IOSForegroundVoiceProcessingFailure,
        VoiceAttemptStage
    )

    var stage: VoiceAttemptStage {
        switch self {
        case .beginning, .transcribing, .transcriptionConsumed:
            .transcription
        case .providerFreePostProcessing, .postProcessing, .finalText:
            .postProcessing
        case .outputDelivery:
            .outputDelivery
        case .recovering(_, _, _, let stage):
            stage
        }
    }

    var recoveryDisposition: IOSForegroundVoiceLocalRecoveryDisposition {
        switch self {
        case .finalText, .outputDelivery:
            .savingResult
        case .beginning,
             .transcribing,
             .transcriptionConsumed,
             .providerFreePostProcessing,
             .postProcessing,
             .recovering:
            .processingCheckpoint
        }
    }
}

private enum IOSForegroundVoiceCorrectionResolution: Sendable {
    case accepted(AcceptedTranscript)
    case recovery(IOSForegroundVoiceProcessingResolution)
}

extension IOSForegroundVoiceProcessor:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public nonisolated var description: String {
        "IOSForegroundVoiceProcessor(redacted)"
    }

    public nonisolated var debugDescription: String { description }
    public nonisolated var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}
