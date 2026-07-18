import Foundation
import HoldTypeDomain
import HoldTypeOpenAI
@_spi(HoldTypeIOSCore) import HoldTypePersistence

protocol IOSForegroundVoicePersisting: Sendable {
    func load() async throws -> IOSV1PendingRecordingObservation?

    func beginTranscription(
        expected: IOSV1PendingRecordingExpectation,
        transcriptionID: UUID
    ) async throws -> IOSV1ForegroundVoiceTranscriptionDispatch

    func retryTranscription(
        expected: IOSV1PendingRecordingExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSV1ForegroundVoiceTranscriptionDispatch

    func checkpointTranscription(
        expected: IOSV1PendingRecordingExpectation,
        acceptedTranscript: String
    ) async throws -> IOSV1PendingRecording

    func checkpointPostProcessing(
        expected: IOSV1PendingRecordingExpectation,
        stage: IOSV1PendingTextCheckpointStage,
        text: String
    ) async throws -> IOSV1PendingRecording

    func retryPostProcessing(
        expected: IOSV1PendingRecordingExpectation,
        operationID: UUID
    ) async throws -> IOSV1PendingRecording

    func markOutputDelivery(
        expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecording

    func markFailed(
        expected: IOSV1PendingRecordingExpectation,
        transcriptionReplayBlocked: Bool
    ) async throws -> IOSV1PendingRecording

    func accept(
        _ preparation: IOSV1ForegroundVoiceAcceptedOutputPreparation,
        expectedPending: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1ForegroundVoiceAcceptanceResult

    func reconcileAcceptance(
        matching preparation: IOSV1ForegroundVoiceAcceptedOutputPreparation
    ) async throws -> IOSV1ForegroundVoiceAcceptanceResult?
}

extension IOSV1ForegroundVoicePersistenceOwner: IOSForegroundVoicePersisting {}

@_spi(HoldTypeIOSCore)
public enum IOSVoiceDraftTextAction: Equatable, Sendable {
    case translate
    case correct
}

@_spi(HoldTypeIOSCore)
public enum IOSVoiceDraftTextActionFailure: Equatable, Sendable {
    case busy
    case invalidText
    case invalidConfiguration
    case credentialUnavailable
    case consentUnavailable
    case networkUnavailable
    case timedOut
    case providerUnavailable
    case invalidResponse
    case draftChanged
    case saveFailed
    case cancelled
}

@_spi(HoldTypeIOSCore)
public enum IOSVoiceDraftTextActionResolution: Equatable, Sendable {
    case success(String)
    case failure(IOSVoiceDraftTextActionFailure)
}

@_spi(HoldTypeIOSCore)
public struct IOSVoiceDraftTextActionRequest: Sendable {
    public let action: IOSVoiceDraftTextAction
    public let text: String
    public let settings: IOSAppSettings
    public let credential: IOSResolvedOpenAICredential
    public let consentObservation: IOSV1ProviderConsentObservation

    public init(
        action: IOSVoiceDraftTextAction,
        text: String,
        settings: IOSAppSettings,
        credential: IOSResolvedOpenAICredential,
        consentObservation: IOSV1ProviderConsentObservation
    ) {
        self.action = action
        self.text = text
        self.settings = settings
        self.credential = credential
        self.consentObservation = consentObservation
    }
}

extension IOSVoiceDraftTextActionRequest:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "IOSVoiceDraftTextActionRequest(redacted)"
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// One process-owned provider pipeline. Durable Pending is the only recovery
/// source: every failed active operation is reduced to `.failed`, and provider
/// work can start again only through a new explicit `.retry` request.
@_spi(HoldTypeIOSCore)
public actor IOSForegroundVoiceProcessor {
    typealias UsageRecorder = @Sendable (
        SuccessfulTranscriptionUsage
    ) async -> Void
    typealias ProviderRejectionRecorder = @Sendable (
        IOSOpenAICredentialGeneration
    ) async -> Void

    private let persistenceOwner: any IOSForegroundVoicePersisting
    private let consentCoordinator: IOSV1ProviderConsentCoordinator
    private let stageExecutor: IOSProviderConsentStageExecutor
    private let provider: IOSForegroundVoiceOpenAIProviderOperations
    private let recordUsage: UsageRecorder
    private let recordProviderRejection: ProviderRejectionRecorder
    private let makeUUID: @Sendable () -> UUID
    private let postProcessor: TranscriptTextPostProcessor

    private var activeOperationID: UUID?

    public init(
        persistenceOwner: IOSV1ForegroundVoicePersistenceOwner,
        consentCoordinator: IOSV1ProviderConsentCoordinator,
        usageRecordingClient: IOSTranscriptionUsageRecordingClient,
        credentialCoordinator: IOSOpenAICredentialCoordinator
    ) {
        self.persistenceOwner = persistenceOwner
        self.consentCoordinator = consentCoordinator
        stageExecutor = IOSProviderConsentStageExecutor(
            consentCoordinator: consentCoordinator
        )
        provider = IOSForegroundVoiceOpenAIProviderOperations()
        recordUsage = { usage in
            await usageRecordingClient.record(usage)
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
        consentCoordinator: IOSV1ProviderConsentCoordinator,
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
        guard let context = makeContext(from: request) else {
            return .notStarted(.invalidConfiguration)
        }
        if context.requiresProviderAuthority {
            guard let consentObservation = context.consentObservation,
                  consentCoordinator.makeAuthorization(
                      from: consentObservation
                  ) != nil else {
                return .notStarted(.providerConsentUnavailable)
            }
        }

        let operationID = UUID()
        activeOperationID = operationID
        defer {
            if activeOperationID == operationID {
                activeOperationID = nil
            }
        }
        return await run(
            context,
            operationID: operationID,
            progress: progress
        )
    }

    /// Runs a provider-only action against an existing app-private Draft. This
    /// shares the Voice processor's operation gate but never creates Pending,
    /// transcription usage, Latest, or History state.
    @_spi(HoldTypeIOSCore)
    public func processDraftText(
        _ request: IOSVoiceDraftTextActionRequest
    ) async -> IOSVoiceDraftTextActionResolution {
        guard activeOperationID == nil else { return .failure(.busy) }
        guard let source = try? AcceptedTranscript(rawText: request.text) else {
            return .failure(.invalidText)
        }
        guard let authorization = consentCoordinator.makeAuthorization(
            from: request.consentObservation
        ) else {
            return .failure(.consentUnavailable)
        }
        if request.action == .translate,
           !request.settings.translationConfiguration.isConfigurationReady {
            return .failure(.invalidConfiguration)
        }

        let operationID = UUID()
        activeOperationID = operationID
        defer {
            if activeOperationID == operationID {
                activeOperationID = nil
            }
        }

        let outcome = await runDraftTextAction(
            request,
            source: source,
            authorization: authorization
        )
        guard activeOperationID == operationID, !Task.isCancelled else {
            return .failure(.cancelled)
        }
        return outcome
    }

    private func runDraftTextAction(
        _ request: IOSVoiceDraftTextActionRequest,
        source: AcceptedTranscript,
        authorization: IOSV1ProviderConsentAuthorization
    ) async -> IOSVoiceDraftTextActionResolution {
        let provider = provider
        let credential = request.credential.credential
        let outcome: IOSProviderConsentStageOutcome<
            AcceptedTranscript,
            IOSForegroundVoiceProviderFailure
        >

        switch request.action {
        case .correct:
            var configuration = request.settings.textCorrectionConfiguration
            configuration.isEnabled = true
            let correctionConfiguration = configuration
            outcome = await stageExecutor.execute(
                authorization,
                for: .correction,
                operation: {
                    try AcceptedTranscript(
                        rawText: try await provider.correct(
                            source,
                            correctionConfiguration,
                            credential
                        )
                    )
                },
                normalizeFailure: {
                    IOSForegroundVoiceProviderFailureMapper.correction($0)
                }
            )
        case .translate:
            let translationRequest = TextTranslationRequest(
                acceptedTranscript: source,
                translationConfiguration:
                    request.settings.translationConfiguration,
                transcriptionConfiguration:
                    request.settings.transcriptionConfiguration
            )
            outcome = await stageExecutor.execute(
                authorization,
                for: .translation,
                operation: {
                    try AcceptedTranscript(
                        rawText: try await provider.translate(
                            translationRequest,
                            credential
                        )
                    )
                },
                normalizeFailure: {
                    IOSForegroundVoiceProviderFailureMapper.translation($0)
                }
            )
        }

        switch outcome {
        case .success(let result):
            return acceptedDraftTextActionResult(
                result,
                source: source,
                action: request.action,
                settings: request.settings
            )
        case .failure(let failure):
            if failure == .credentialRejected {
                await recordProviderRejection(request.credential.generation)
            }
            return .failure(Self.draftTextActionFailure(from: failure))
        case .cancelled:
            return .failure(.cancelled)
        case .authorizationUnavailable:
            return .failure(.consentUnavailable)
        }
    }

    private func acceptedDraftTextActionResult(
        _ result: AcceptedTranscript,
        source: AcceptedTranscript,
        action: IOSVoiceDraftTextAction,
        settings: IOSAppSettings
    ) -> IOSVoiceDraftTextActionResolution {
        if action == .correct,
           !Self.isSafeCorrection(
               original: source.text,
               corrected: result.text
           ) {
            return .success(source.text)
        }
        guard action == .translate, settings.localTextCleanupEnabled else {
            return .success(result.text)
        }
        let normalized = TranscriptTextPostProcessor
            .normalizedInformalTypography(
                from: result.text,
                fallback: result.text
            )
        guard let accepted = try? AcceptedTranscript(rawText: normalized) else {
            return .failure(.invalidResponse)
        }
        return .success(accepted.text)
    }

    private static func draftTextActionFailure(
        from failure: IOSForegroundVoiceProviderFailure
    ) -> IOSVoiceDraftTextActionFailure {
        switch failure {
        case .credentialMissing, .credentialUnavailable, .credentialRejected:
            .credentialUnavailable
        case .networkUnavailable:
            .networkUnavailable
        case .timedOut:
            .timedOut
        case .invalidRequest, .invalidTranslationRoute:
            .invalidConfiguration
        case .invalidResponse, .emptyResult, .dictionaryEcho, .contextEcho:
            .invalidResponse
        case .cancelled:
            .cancelled
        case .networkFailure, .rateLimited, .providerUnavailable,
             .badRequest, .providerRejected, .unknown:
            .providerUnavailable
        case .invalidRecording, .multipartMetadataTooLarge:
            .invalidResponse
        }
    }

    private func run(
        _ context: IOSForegroundVoicePipelineContext,
        operationID: UUID,
        progress: @escaping IOSForegroundVoiceProcessingProgressHandler
    ) async -> IOSForegroundVoiceProcessingResolution {
        guard activeOperationID == operationID,
              !processingWasCancelled(context) else {
            return .notStarted(.cancelled)
        }

        var postProcessing: IOSV1PendingRecording
        if context.mode == .retry,
           context.pendingRecording.acceptedTranscriptionID != nil,
           context.pendingRecording.textCheckpointStage != nil,
           context.pendingRecording.textCheckpointText != nil {
            guard context.pendingRecording.textCheckpointStage
                    != .translationInFlight else {
                return .notStarted(.localPersistence)
            }
            do {
                postProcessing = try await resumePostProcessing(
                    context.pendingRecording,
                    operationID: context.transcriptionID
                )
            } catch {
                return await persistFailure(
                    from: context.pendingRecording,
                    failure: .localPersistence,
                    stage: .postProcessing
                )
            }
        } else {
            let dispatchSource: IOSV1PendingRecording
            switch context.mode {
            case .initial:
                dispatchSource = context.pendingRecording
            case .retry where context.pendingRecording.phase
                == .readyForTranscription:
                do {
                    let failed = try await persistenceOwner.markFailed(
                        expected: IOSV1PendingRecordingExpectation(
                            recording: context.pendingRecording
                        ),
                        transcriptionReplayBlocked: false
                    )
                    dispatchSource = try await canonicalRecording(
                        continuing: failed,
                        phase: .failed
                    )
                } catch {
                    guard let observed = try? await persistenceOwner.load()?
                        .recording,
                        Self.continuesAttempt(
                            observed,
                            from: context.pendingRecording
                        ),
                        observed.phase == .failed else {
                        return .notStarted(.localPersistence)
                    }
                    dispatchSource = observed
                }
            case .retry:
                dispatchSource = context.pendingRecording
            }

            let dispatch: IOSV1ForegroundVoiceTranscriptionDispatch
            do {
                switch context.mode {
                case .initial:
                    dispatch = try await persistenceOwner.beginTranscription(
                        expected: IOSV1PendingRecordingExpectation(
                            recording: dispatchSource
                        ),
                        transcriptionID: context.transcriptionID
                    )
                case .retry:
                    dispatch = try await persistenceOwner.retryTranscription(
                        expected: IOSV1PendingRecordingExpectation(
                            recording: dispatchSource
                        ),
                        transcriptionID: context.transcriptionID,
                        transcriptionConfiguration:
                            context.transcriptionConfiguration
                    )
                }
            } catch {
                return await reconcileBeginFailure(
                    context,
                    dispatchSource: dispatchSource
                )
            }

            let transcribing: IOSV1PendingRecording
            do {
                transcribing = try await canonicalRecording(
                    continuing: dispatch.recording,
                    phase: .transcribing
                )
            } catch {
                return await persistFailure(
                    from: dispatch.recording,
                    failure: .localPersistence,
                    stage: .transcription
                )
            }
            guard activeOperationID == operationID,
                  !processingWasCancelled(context) else {
                return await persistFailure(
                    from: transcribing,
                    failure: .cancelled,
                    stage: .transcription
                )
            }
            await progress(.transcription)
            guard activeOperationID == operationID,
                  !processingWasCancelled(context) else {
                return await persistFailure(
                    from: transcribing,
                    failure: .cancelled,
                    stage: .transcription
                )
            }
            guard let consentObservation = context.consentObservation,
                  let credential = context.credential?.credential,
                  let authorization = consentCoordinator.makeAuthorization(
                      from: consentObservation
                  ) else {
                return await persistFailure(
                    from: transcribing,
                    failure: context.consentObservation == nil
                        ? .providerConsentUnavailable : .credentialRejected,
                    stage: .transcription
                )
            }

            let providerDispatchEvidence =
                IOSForegroundVoiceProviderDispatchEvidence()
            let provider = provider
            let instrumentedProvider =
                IOSForegroundVoiceOpenAIProviderOperations(
                    transcribe: { request, credential in
                        providerDispatchEvidence.recordLaunch()
                        return try await provider.transcribe(
                            request,
                            credential
                        )
                    },
                    correct: provider.correct,
                    translate: provider.translate
                )
            let executor = IOSForegroundVoiceTranscriptionExecutor(
                authorization: authorization,
                stageExecutor: stageExecutor,
                provider: instrumentedProvider,
                credential: credential,
                promptComposition: context.promptComposition
            )
            let accepted: AcceptedTranscript
            do {
                accepted = try AcceptedTranscript(
                    rawText: try await dispatch.execute(using: executor)
                )
            } catch let error as IOSForegroundVoiceTranscriptionStageError {
                let failure: IOSForegroundVoiceProcessingFailure
                switch error {
                case .failure(let providerFailure):
                    await recordCredentialRejectionIfNeeded(
                        providerFailure,
                        context: context
                    )
                    failure = providerFailure.publicFailure
                case .cancelled:
                    failure = .cancelled
                case .authorizationUnavailable:
                    failure = .providerConsentUnavailable
                }
                return await persistFailure(
                    from: transcribing,
                    failure: processingWasCancelled(context)
                        ? .cancelled : failure,
                    stage: .transcription,
                    transcriptionReplayBlocked:
                        providerDispatchEvidence.didLaunch
                        && (processingWasCancelled(context)
                            || Self.hasAmbiguousTranscriptionOutcome(error))
                )
            } catch {
                return await persistFailure(
                    from: transcribing,
                    failure: processingWasCancelled(context)
                        ? .cancelled : .invalidRecording,
                    stage: .transcription,
                    transcriptionReplayBlocked:
                        providerDispatchEvidence.didLaunch
                )
            }

            guard !processingWasCancelled(context) else {
                return await persistFailure(
                    from: transcribing,
                    failure: .cancelled,
                    stage: .transcription,
                    transcriptionReplayBlocked:
                        providerDispatchEvidence.didLaunch
                )
            }

            await recordSuccessfulTranscriptionUsage(
                context: context,
                recording: transcribing
            )
            do {
                postProcessing = try await checkpointAcceptedTranscript(
                    accepted,
                    from: transcribing
                )
            } catch {
                // The durable transcribing owner is replay evidence after its
                // one-shot dispatch has returned. Do not turn an uncertain
                // checkpoint write into an audio-authorized failed retry.
                return .notStarted(.localPersistence)
            }
            guard !processingWasCancelled(context) else {
                return await persistFailure(
                    from: postProcessing,
                    failure: .cancelled,
                    stage: .postProcessing
                )
            }
        }
        await progress(.postProcessing)
        guard !processingWasCancelled(context) else {
            return await persistFailure(
                from: postProcessing,
                failure: .cancelled,
                stage: .postProcessing
            )
        }

        let finalText: AcceptedTranscript
        switch await resolvePostProcessing(
            from: postProcessing,
            context: context
        ) {
        case .output(let text, let checkpointed):
            finalText = text
            postProcessing = checkpointed
        case .failure(let failure, let checkpointed):
            return await persistFailure(
                from: checkpointed,
                failure: failure,
                stage: .postProcessing
            )
        }

        let outputDelivery: IOSV1PendingRecording
        do {
            outputDelivery = try await advanceToOutputDelivery(postProcessing)
        } catch {
            return await persistFailure(
                from: postProcessing,
                failure: .localPersistence,
                stage: .postProcessing
            )
        }
        await progress(.outputDelivery)
        guard !processingWasCancelled(context) else {
            return await persistFailure(
                from: outputDelivery,
                failure: .cancelled,
                stage: .outputDelivery
            )
        }

        let preparation: IOSV1ForegroundVoiceAcceptedOutputPreparation
        do {
            preparation = try IOSV1ForegroundVoiceAcceptedOutputPreparation(
                deliveryID: context.deliveryID,
                sessionID: context.sessionID,
                attemptID: outputDelivery.attemptID,
                transcriptID: context.transcriptionID,
                rawAcceptedText: finalText.text,
                outputIntent: context.outputIntent
            )
        } catch {
            return await persistFailure(
                from: outputDelivery,
                failure: .invalidConfiguration,
                stage: .outputDelivery
            )
        }

        guard !processingWasCancelled(context) else {
            return await persistFailure(
                from: outputDelivery,
                failure: .cancelled,
                stage: .outputDelivery
            )
        }

        do {
            return .acceptance(
                try await persistenceOwner.accept(
                    preparation,
                    expectedPending: IOSV1PendingRecordingExpectation(
                        recording: outputDelivery
                    )
                )
            )
        } catch {
            do {
                if let result = try await persistenceOwner
                    .reconcileAcceptance(matching: preparation) {
                    return .acceptance(result)
                }
            } catch {
                if await acceptanceCleanupIsPending(
                    attemptID: outputDelivery.attemptID
                ) {
                    return .notStarted(.localPersistence)
                }
            }
            return await persistFailure(
                from: outputDelivery,
                failure: .localPersistence,
                stage: .outputDelivery
            )
        }
    }

    private func resolvePostProcessing(
        from recording: IOSV1PendingRecording,
        context: IOSForegroundVoicePipelineContext
    ) async -> IOSForegroundVoicePostProcessingResolution {
        guard !processingWasCancelled(context) else {
            return .failure(.cancelled, recording)
        }
        guard let stage = recording.textCheckpointStage,
              let rawText = recording.textCheckpointText,
              let retained = try? AcceptedTranscript(rawText: rawText) else {
            return .failure(.localPersistence, recording)
        }

        switch stage {
        case .outputReady:
            return .output(retained, recording)
        case .translationInFlight:
            // A prior Translation launch has no confirmed result. The retained
            // evidence is deliberately not provider-authorized for replay.
            return .failure(.localPersistence, recording)
        case .translationReady:
            return await translateRetainedText(
                retained,
                recording: recording,
                context: context
            )
        case .correctionInFlight:
            // Correction is fail-open. Once launch is durable but its result is
            // unknown, resume locally from the pre-correction text and never
            // issue a replacement correction request.
            return await finishLocallyProcessedText(
                retained,
                recording: recording,
                context: context
            )
        case .transcriptionAccepted:
            var checkpointed = recording
            var source = retained
            if context.correctionConfiguration.isEnabled {
                do {
                    checkpointed = try await checkpointPostProcessingText(
                        retained,
                        stage: .correctionInFlight,
                        from: checkpointed
                    )
                } catch {
                    return .failure(.localPersistence, checkpointed)
                }
                source = await correctedTranscript(retained, context: context)
                guard !processingWasCancelled(context) else {
                    return .failure(.cancelled, checkpointed)
                }
            }
            return await finishLocallyProcessedText(
                source,
                recording: checkpointed,
                context: context
            )
        }
    }

    private func finishLocallyProcessedText(
        _ source: AcceptedTranscript,
        recording: IOSV1PendingRecording,
        context: IOSForegroundVoicePipelineContext
    ) async -> IOSForegroundVoicePostProcessingResolution {
        guard !processingWasCancelled(context) else {
            return .failure(.cancelled, recording)
        }
        let processedText = postProcessor.process(
            source.text,
            configuration: context.postProcessingConfiguration,
            fallback: source.text
        )
        guard let processed = try? AcceptedTranscript(rawText: processedText)
        else {
            return .failure(.invalidConfiguration, recording)
        }

        let checkpointed: IOSV1PendingRecording
        do {
            switch recording.outputIntent {
            case .standard:
                checkpointed = try await checkpointPostProcessingText(
                    processed,
                    stage: .outputReady,
                    from: recording
                )
                return .output(processed, checkpointed)
            case .translate:
                checkpointed = try await checkpointPostProcessingText(
                    processed,
                    stage: .translationReady,
                    from: recording
                )
            }
        } catch {
            return .failure(.localPersistence, recording)
        }
        return await translateRetainedText(
            processed,
            recording: checkpointed,
            context: context
        )
    }

    private func translateRetainedText(
        _ source: AcceptedTranscript,
        recording: IOSV1PendingRecording,
        context: IOSForegroundVoicePipelineContext
    ) async -> IOSForegroundVoicePostProcessingResolution {
        let inFlight: IOSV1PendingRecording
        do {
            inFlight = try await checkpointPostProcessingText(
                source,
                stage: .translationInFlight,
                from: recording
            )
        } catch {
            return .failure(.localPersistence, recording)
        }

        switch await translatedTranscript(source, context: context) {
        case .success(let translated):
            do {
                let outputReady = try await checkpointPostProcessingText(
                    translated,
                    stage: .outputReady,
                    from: inFlight
                )
                return .output(translated, outputReady)
            } catch {
                // Translation may have completed, so the in-flight seal must
                // remain the retry boundary when its result cannot be proven.
                return .failure(.localPersistence, inFlight)
            }
        case .failure(let failure):
            guard failure != .cancelled else {
                return .failure(failure, inFlight)
            }
            do {
                let retryable = try await checkpointPostProcessingText(
                    source,
                    stage: .translationReady,
                    from: inFlight
                )
                return .failure(failure, retryable)
            } catch {
                return .failure(.localPersistence, inFlight)
            }
        }
    }

    private func correctedTranscript(
        _ transcript: AcceptedTranscript,
        context: IOSForegroundVoicePipelineContext
    ) async -> AcceptedTranscript {
        guard context.correctionConfiguration.isEnabled,
              let consentObservation = context.consentObservation,
              let credential = context.credential?.credential,
              let authorization = consentCoordinator.makeAuthorization(
                  from: consentObservation
              ) else {
            return transcript
        }
        let provider = provider
        let configuration = context.correctionConfiguration
        let outcome: IOSProviderConsentStageOutcome<
            AcceptedTranscript,
            IOSForegroundVoiceProviderFailure
        > = await stageExecutor.execute(
            authorization,
            for: .correction,
            operation: {
                try AcceptedTranscript(
                    rawText: try await provider.correct(
                        transcript,
                        configuration,
                        credential
                    )
                )
            },
            normalizeFailure: {
                IOSForegroundVoiceProviderFailureMapper.correction($0)
            }
        )
        switch outcome {
        case .success(let candidate)
            where Self.isSafeCorrection(
                original: transcript.text,
                corrected: candidate.text
            ):
            return candidate
        case .failure(let failure):
            await recordCredentialRejectionIfNeeded(failure, context: context)
            return transcript
        case .success, .cancelled, .authorizationUnavailable:
            return transcript
        }
    }

    private func translatedTranscript(
        _ transcript: AcceptedTranscript,
        context: IOSForegroundVoicePipelineContext
    ) async -> IOSForegroundVoiceTextResolution {
        guard let translation = context.translationConfiguration else {
            return .failure(.invalidConfiguration)
        }
        guard let consentObservation = context.consentObservation,
              let credential = context.credential?.credential,
              let authorization = consentCoordinator.makeAuthorization(
                  from: consentObservation
              ) else {
            return .failure(
                context.consentObservation == nil
                    ? .providerConsentUnavailable : .credentialRejected
            )
        }
        let provider = provider
        let transcriptionConfiguration = context.transcriptionConfiguration
        let outcome: IOSProviderConsentStageOutcome<
            AcceptedTranscript,
            IOSForegroundVoiceProviderFailure
        > = await stageExecutor.execute(
            authorization,
            for: .translation,
            operation: {
                try AcceptedTranscript(
                    rawText: try await provider.translate(
                        TextTranslationRequest(
                            acceptedTranscript: transcript,
                            translationConfiguration: translation,
                            transcriptionConfiguration:
                                transcriptionConfiguration
                        ),
                        credential
                    )
                )
            },
            normalizeFailure: {
                IOSForegroundVoiceProviderFailureMapper.translation($0)
            }
        )
        guard !processingWasCancelled(context) else {
            return .failure(.cancelled)
        }
        switch outcome {
        case .success(let translated):
            guard context.postProcessingConfiguration
                .localTextCleanupEnabled else {
                return .success(translated)
            }
            let normalized = TranscriptTextPostProcessor
                .normalizedInformalTypography(
                    from: translated.text,
                    fallback: translated.text
                )
            guard let accepted = try? AcceptedTranscript(rawText: normalized)
            else { return .failure(.invalidResponse) }
            return .success(accepted)
        case .failure(let failure):
            await recordCredentialRejectionIfNeeded(failure, context: context)
            return .failure(failure.publicFailure)
        case .cancelled:
            return .failure(.cancelled)
        case .authorizationUnavailable:
            return .failure(.providerConsentUnavailable)
        }
    }

    private func reconcileBeginFailure(
        _ context: IOSForegroundVoicePipelineContext,
        dispatchSource: IOSV1PendingRecording
    ) async -> IOSForegroundVoiceProcessingResolution {
        let observation: IOSV1PendingRecordingObservation?
        do {
            observation = try await persistenceOwner.load()
        } catch {
            return .notStarted(.localPersistence)
        }
        guard let current = observation?.recording,
              Self.continuesAttempt(
                  current,
                  from: dispatchSource
              ) else {
            return .notStarted(.localPersistence)
        }
        return await persistFailure(
            from: current,
            failure: processingWasCancelled(context)
                ? .cancelled : .localPersistence,
            stage: .transcription
        )
    }

    private func checkpointAcceptedTranscript(
        _ transcript: AcceptedTranscript,
        from source: IOSV1PendingRecording
    ) async throws -> IOSV1PendingRecording {
        guard let transcriptionID = source.transcriptionID else {
            throw IOSForegroundVoiceCanonicalizationError.unavailable
        }
        do {
            let checkpointed = try await persistenceOwner
                .checkpointTranscription(
                    expected: IOSV1PendingRecordingExpectation(
                        recording: source
                    ),
                    acceptedTranscript: transcript.text
                )
            let canonical = try await canonicalRecording(
                continuing: checkpointed,
                phase: .postProcessing
            )
            guard canonical.textCheckpointStage == .transcriptionAccepted,
                  canonical.textCheckpointText == transcript.text else {
                throw IOSForegroundVoiceCanonicalizationError.unavailable
            }
            return canonical
        } catch {
            guard let current = try await persistenceOwner.load()?.recording,
                  Self.continuesAttempt(current, from: source),
                  current.phase == .postProcessing,
                  current.transcriptionID == transcriptionID,
                  current.acceptedTranscriptionID == transcriptionID,
                  current.acceptedTranscript == transcript.text else {
                throw error
            }
            return current
        }
    }

    private func checkpointPostProcessingText(
        _ text: AcceptedTranscript,
        stage: IOSV1PendingTextCheckpointStage,
        from source: IOSV1PendingRecording
    ) async throws -> IOSV1PendingRecording {
        guard let operationID = source.transcriptionID,
              source.phase == .postProcessing else {
            throw IOSForegroundVoiceCanonicalizationError.unavailable
        }
        do {
            let checkpointed = try await persistenceOwner
                .checkpointPostProcessing(
                    expected: IOSV1PendingRecordingExpectation(
                        recording: source
                    ),
                    stage: stage,
                    text: text.text
                )
            let canonical = try await canonicalRecording(
                continuing: checkpointed,
                phase: .postProcessing
            )
            guard canonical.textCheckpointStage == stage,
                  canonical.textCheckpointText == text.text else {
                throw IOSForegroundVoiceCanonicalizationError.unavailable
            }
            return canonical
        } catch {
            guard let current = try await persistenceOwner.load()?.recording,
                  Self.continuesAttempt(current, from: source),
                  current.phase == .postProcessing,
                  current.transcriptionID == operationID,
                  current.textCheckpointStage == stage,
                  current.textCheckpointText == text.text else {
                throw error
            }
            return current
        }
    }

    private func resumePostProcessing(
        _ source: IOSV1PendingRecording,
        operationID: UUID
    ) async throws -> IOSV1PendingRecording {
        guard source.phase == .failed,
              source.acceptedTranscriptionID != nil,
              source.acceptedTranscript != nil else {
            throw IOSForegroundVoiceCanonicalizationError.unavailable
        }
        do {
            let resumed = try await persistenceOwner.retryPostProcessing(
                expected: IOSV1PendingRecordingExpectation(recording: source),
                operationID: operationID
            )
            return try await canonicalRecording(
                continuing: resumed,
                phase: .postProcessing
            )
        } catch {
            guard let current = try await persistenceOwner.load()?.recording,
                  Self.continuesAttempt(current, from: source),
                  current.phase == .postProcessing,
                  current.transcriptionID == operationID,
                  current.acceptedTranscriptionID
                    == source.acceptedTranscriptionID,
                  current.acceptedTranscript == source.acceptedTranscript else {
                throw error
            }
            return current
        }
    }

    private func advanceToOutputDelivery(
        _ source: IOSV1PendingRecording
    ) async throws -> IOSV1PendingRecording {
        do {
            let advanced = try await persistenceOwner.markOutputDelivery(
                expected: IOSV1PendingRecordingExpectation(recording: source)
            )
            return try await canonicalRecording(
                continuing: advanced,
                phase: .outputDelivery
            )
        } catch {
            guard let current = try await persistenceOwner.load()?.recording,
                  Self.continuesAttempt(current, from: source),
                  current.phase == .outputDelivery,
                  current.transcriptionID == source.transcriptionID else {
                throw error
            }
            return current
        }
    }

    private func persistFailure(
        from source: IOSV1PendingRecording,
        failure: IOSForegroundVoiceProcessingFailure,
        stage: VoiceAttemptStage,
        transcriptionReplayBlocked: Bool = false
    ) async -> IOSForegroundVoiceProcessingResolution {
        let current: IOSV1PendingRecording
        do {
            guard let observed = try await persistenceOwner.load()?.recording,
                  Self.continuesAttempt(observed, from: source) else {
                return .notStarted(.localPersistence)
            }
            current = observed
        } catch {
            return .notStarted(.localPersistence)
        }
        if current.phase == .failed,
           (!transcriptionReplayBlocked
                || current.transcriptionReplayBlocked) {
            return .retryAvailable(current, failure: failure, stage: stage)
        }
        guard current.phase != .acceptedCleanup else {
            return .notStarted(.localPersistence)
        }

        let owner = persistenceOwner
        let expectation = IOSV1PendingRecordingExpectation(recording: current)
        let result = await Task {
            try await owner.markFailed(
                expected: expectation,
                transcriptionReplayBlocked: transcriptionReplayBlocked
            )
        }.result
        if case .success(let failed) = result,
           let canonical = try? await canonicalRecording(
               continuing: failed,
               phase: .failed
           ) {
            return .retryAvailable(canonical, failure: failure, stage: stage)
        }
        if let observed = try? await persistenceOwner.load()?.recording,
           Self.continuesAttempt(observed, from: source),
           observed.phase == .failed {
            return .retryAvailable(observed, failure: failure, stage: stage)
        }
        return .notStarted(.localPersistence)
    }

    private static func hasAmbiguousTranscriptionOutcome(
        _ error: IOSForegroundVoiceTranscriptionStageError
    ) -> Bool {
        switch error {
        case .failure(.networkUnavailable), .failure(.networkFailure),
             .failure(.timedOut), .failure(.cancelled),
             .failure(.unknown), .cancelled:
            true
        case .failure, .authorizationUnavailable:
            false
        }
    }

    private func processingWasCancelled(
        _ context: IOSForegroundVoicePipelineContext
    ) -> Bool {
        Task.isCancelled
            || context.cancellationAuthority.isExplicitlyCancelled
    }

    private func canonicalRecording(
        continuing source: IOSV1PendingRecording,
        phase: IOSV1PendingRecordingPhase
    ) async throws -> IOSV1PendingRecording {
        guard let current = try await persistenceOwner.load()?.recording,
              Self.continuesAttempt(current, from: source),
              current.phase == phase,
              current.transcriptionID == source.transcriptionID else {
            throw IOSForegroundVoiceCanonicalizationError.unavailable
        }
        return current
    }

    private func acceptanceCleanupIsPending(attemptID: UUID) async -> Bool {
        let observation: IOSV1PendingRecordingObservation?
        do {
            observation = try await persistenceOwner.load()
        } catch {
            return false
        }
        guard let recording = observation?.recording else { return false }
        return recording.attemptID == attemptID
            && recording.phase == .acceptedCleanup
    }

    private func makeContext(
        from request: IOSForegroundVoiceProcessingRequest
    ) -> IOSForegroundVoicePipelineContext? {
        let pending = request.pendingRecording
        switch request.mode {
        case .initial:
            guard pending.phase == .readyForTranscription,
                  pending.transcriptionID == nil else { return nil }
        case .retry:
            guard (pending.phase == .readyForTranscription
                    || pending.phase == .failed),
                  pending.transcriptionID == nil else { return nil }
        }
        let transcription = request.settings.transcriptionConfiguration
        let providerFreeRetry: Bool
        if request.mode == .retry {
            providerFreeRetry = switch pending.textCheckpointStage {
            case .outputReady, .translationInFlight:
                true
            case .correctionInFlight:
                pending.outputIntent == .standard
            case .transcriptionAccepted:
                pending.outputIntent == .standard
                    && !request.settings.textCorrectionConfiguration.isEnabled
                    && !request.forcesTextCorrection
            case .translationReady:
                false
            case nil:
                pending.transcriptionReplayBlocked
            }
        } else {
            providerFreeRetry = false
        }
        guard providerFreeRetry
            || !transcription.customLanguageCodeValidation.isInvalid else {
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
            if providerFreeRetry {
                translation = nil
            } else if request.settings.translationConfiguration
                .isConfigurationReady {
                translation = request.settings.translationConfiguration
            } else {
                return nil
            }
        }
        var correction = request.settings.textCorrectionConfiguration
        if request.forcesTextCorrection {
            correction.isEnabled = true
        }
        return IOSForegroundVoicePipelineContext(
            sessionID: request.sessionID,
            pendingRecording: pending,
            mode: request.mode,
            transcriptionConfiguration: transcription,
            correctionConfiguration: correction,
            translationConfiguration: translation,
            postProcessingConfiguration:
                TranscriptPostProcessingConfiguration(
                    localTextCleanupEnabled:
                        request.settings.localTextCleanupEnabled,
                    emojiCommands:
                        request.library.emojiCommandsConfiguration,
                    textReplacementRules: request.library.replacementRules
                ),
            promptComposition: TranscriptionPromptComposition(
                resolvedFreeformPrompt:
                    transcription.resolvedFreeformPrompt,
                context: nil,
                emojiCommandsConfiguration:
                    request.library.emojiCommandsConfiguration,
                customDictionary: request.library.customDictionary
            ),
            credential: request.credential,
            consentObservation: request.consentObservation,
            cancellationAuthority: request.cancellationAuthority,
            transcriptionID: makeUUID(),
            deliveryID: makeUUID()
        )
    }

    private func recordCredentialRejectionIfNeeded(
        _ failure: IOSForegroundVoiceProviderFailure,
        context: IOSForegroundVoicePipelineContext
    ) async {
        guard failure == .credentialRejected else { return }
        guard let credential = context.credential else { return }
        await recordProviderRejection(credential.generation)
    }

    private func recordSuccessfulTranscriptionUsage(
        context: IOSForegroundVoicePipelineContext,
        recording: IOSV1PendingRecording
    ) async {
        guard let usage = try? SuccessfulTranscriptionUsage(
            transcriptionID: context.transcriptionID,
            model: recording.transcriptionModel,
            audioDuration:
                TimeInterval(recording.durationMilliseconds) / 1_000
        ) else { return }
        let recorder = recordUsage
        await Task { await recorder(usage) }.value
    }

    private static func continuesAttempt(
        _ candidate: IOSV1PendingRecording,
        from source: IOSV1PendingRecording
    ) -> Bool {
        candidate.attemptID == source.attemptID
            && candidate.audioRelativeIdentifier
                == source.audioRelativeIdentifier
            && candidate.createdAt == source.createdAt
            && candidate.updatedAt.timeIntervalSince(source.updatedAt)
                >= -0.001
            && candidate.outputIntent == source.outputIntent
            && candidate.transcriptionModel == source.transcriptionModel
            && candidate.transcriptionLanguageCode
                == source.transcriptionLanguageCode
            && candidate.durationMilliseconds == source.durationMilliseconds
            && candidate.byteCount == source.byteCount
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

private final class IOSForegroundVoiceProviderDispatchEvidence:
    @unchecked Sendable {
    private let lock = NSLock()
    private var launched = false

    var didLaunch: Bool { lock.withLock { launched } }

    func recordLaunch() {
        lock.withLock { launched = true }
    }
}

private struct IOSForegroundVoicePipelineContext: Sendable {
    let sessionID: UUID
    let pendingRecording: IOSV1PendingRecording
    let mode: IOSForegroundVoiceProcessingMode
    let transcriptionConfiguration: TranscriptionConfiguration
    let correctionConfiguration: TextCorrectionConfiguration
    let translationConfiguration: TranslationConfiguration?
    let postProcessingConfiguration: TranscriptPostProcessingConfiguration
    let promptComposition: TranscriptionPromptComposition
    let credential: IOSResolvedOpenAICredential?
    let consentObservation: IOSV1ProviderConsentObservation?
    let cancellationAuthority:
        IOSForegroundVoiceProcessingCancellationAuthority
    let transcriptionID: UUID
    let deliveryID: UUID

    var outputIntent: DictationOutputIntent {
        pendingRecording.outputIntent
    }

    var requiresProviderAuthority: Bool {
        guard mode == .retry else { return true }
        guard let stage = pendingRecording.textCheckpointStage else {
            return !pendingRecording.transcriptionReplayBlocked
        }
        return switch stage {
        case .outputReady, .translationInFlight:
            false
        case .translationReady:
            true
        case .correctionInFlight:
            outputIntent == .translate
        case .transcriptionAccepted:
            correctionConfiguration.isEnabled || outputIntent == .translate
        }
    }
}

private enum IOSForegroundVoiceTextResolution: Sendable {
    case success(AcceptedTranscript)
    case failure(IOSForegroundVoiceProcessingFailure)
}

private enum IOSForegroundVoicePostProcessingResolution: Sendable {
    case output(AcceptedTranscript, IOSV1PendingRecording)
    case failure(
        IOSForegroundVoiceProcessingFailure,
        IOSV1PendingRecording
    )
}

private enum IOSForegroundVoiceCanonicalizationError: Error {
    case unavailable
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
