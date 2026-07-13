import Foundation
import HoldTypeDomain

/// Payload-free provider outcome accepted by the app-owned Retry adapter.
/// Provider status codes, localized errors, credentials, and response payloads
/// must be discarded before this boundary.
@_spi(HoldTypeIOSCore)
public enum IOSFailedHistoryRetryRuntimeFailure:
    CaseIterable,
    Equatable,
    Sendable {
    case credentialMissing
    case credentialUnavailable
    case credentialRejected
    case networkUnavailable
    case networkFailure
    case timedOut
    case rateLimited
    case providerUnavailable
    case badRequest
    case providerRejected
    case invalidResponse
    case emptyResult
    case dictionaryEcho
    case contextEcho
    case invalidRecording
    case invalidRequest
    case multipartMetadataTooLarge
    case invalidTranslationRoute
    case authorizationUnavailable
    case cancelled
    case unknown

    func durableCategory(
        at stage: IOSFailedHistoryPipelineStage
    ) -> IOSFailedHistoryFailureCategory? {
        switch self {
        case .credentialMissing, .credentialUnavailable,
                .credentialRejected:
            .credentialRejected
        case .networkUnavailable:
            .networkUnavailable
        case .networkFailure:
            .networkFailure
        case .timedOut:
            .timedOut
        case .rateLimited:
            .rateLimited
        case .providerUnavailable:
            .providerUnavailable
        case .badRequest, .providerRejected:
            .providerRejected
        case .invalidResponse:
            .invalidResponse
        case .emptyResult:
            .emptyResult
        case .dictionaryEcho, .contextEcho:
            stage == .transcription ? .echoRejected : nil
        case .invalidRecording, .invalidRequest,
                .multipartMetadataTooLarge, .invalidTranslationRoute,
                .authorizationUnavailable, .cancelled, .unknown:
            nil
        }
    }
}

@_spi(HoldTypeIOSCore)
public enum IOSFailedHistoryRetryProviderTextOutcome: Equatable, Sendable {
    case success(String)
    case failure(IOSFailedHistoryRetryRuntimeFailure)
}

@_spi(HoldTypeIOSCore)
public struct IOSFailedHistoryRetryTranscriptionRequest: Sendable {
    public let transcriptionID: UUID
    public let audio: IOSPendingTranscriptionAudio
    public let resolvedModel: String
    public let resolvedLanguageCode: String?
    public let promptComposition: TranscriptionPromptComposition
    public let timeout: Duration

    public init(
        transcriptionID: UUID,
        audio: IOSPendingTranscriptionAudio,
        resolvedModel: String,
        resolvedLanguageCode: String?,
        promptComposition: TranscriptionPromptComposition,
        timeout: Duration
    ) {
        self.transcriptionID = transcriptionID
        self.audio = audio
        self.resolvedModel = resolvedModel
        self.resolvedLanguageCode = resolvedLanguageCode
        self.promptComposition = promptComposition
        self.timeout = timeout
    }
}

@_spi(HoldTypeIOSCore)
public struct IOSFailedHistoryRetryCorrectionRequest: Equatable, Sendable {
    public let transcript: AcceptedTranscript
    public let configuration: TextCorrectionConfiguration
    public let timeout: Duration

    public init(
        transcript: AcceptedTranscript,
        configuration: TextCorrectionConfiguration,
        timeout: Duration
    ) {
        self.transcript = transcript
        self.configuration = configuration
        self.timeout = timeout
    }
}

@_spi(HoldTypeIOSCore)
public struct IOSFailedHistoryRetryTranslationRequest: Equatable, Sendable {
    public let translationRequest: TextTranslationRequest
    public let timeout: Duration

    public init(
        translationRequest: TextTranslationRequest,
        timeout: Duration
    ) {
        self.translationRequest = translationRequest
        self.timeout = timeout
    }
}

@_spi(HoldTypeIOSCore)
public protocol IOSFailedHistoryRetryProviderExecuting: Sendable {
    /// Every adapter call must finish within its own bounded transport/local-
    /// I/O cancellation contract. The pipeline retires stage authority first,
    /// then drains only this adapter task; abandoned lower-layer work must not
    /// escape the adapter or publish a late result.
    func transcribe(
        _ request: IOSFailedHistoryRetryTranscriptionRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome

    func correct(
        _ request: IOSFailedHistoryRetryCorrectionRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome

    func translate(
        _ request: IOSFailedHistoryRetryTranslationRequest
    ) async -> IOSFailedHistoryRetryProviderTextOutcome
}

protocol IOSFailedHistoryRetryUsageRecording: Sendable {
    func recordRetryUsage(
        _ usage: SuccessfulTranscriptionUsage
    ) async throws
}

extension IOSTranscriptionUsageRecordingClient:
    IOSFailedHistoryRetryUsageRecording {
    func recordRetryUsage(
        _ usage: SuccessfulTranscriptionUsage
    ) async throws {
        await record(usage)
    }
}

protocol IOSFailedHistoryRetryTimeoutSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct IOSFailedHistoryRetryContinuousClockSleeper:
    IOSFailedHistoryRetryTimeoutSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task<Never, Never>.sleep(for: duration)
    }
}

struct IOSFailedHistoryRetryProviderTimeouts: Equatable, Sendable {
    static let defaults = IOSFailedHistoryRetryProviderTimeouts(
        uncheckedTranscription: .seconds(60),
        correction: .seconds(20),
        translation: .seconds(20)
    )

    let transcription: Duration
    let correction: Duration
    let translation: Duration

    init(
        transcription: Duration,
        correction: Duration,
        translation: Duration
    ) throws {
        guard transcription > .zero,
              correction > .zero,
              translation > .zero else {
            throw IOSFailedHistoryError.invalidTransition
        }
        self.transcription = transcription
        self.correction = correction
        self.translation = translation
    }

    private init(
        uncheckedTranscription transcription: Duration,
        correction: Duration,
        translation: Duration
    ) {
        self.transcription = transcription
        self.correction = correction
        self.translation = translation
    }
}

struct IOSFailedHistoryRetryPipelineFailure: Equatable, Sendable {
    let runtimeFailure: IOSFailedHistoryRetryRuntimeFailure
    let stage: IOSFailedHistoryPipelineStage

    var durableCategory: IOSFailedHistoryFailureCategory? {
        runtimeFailure.durableCategory(at: stage)
    }
}

enum IOSFailedHistoryRetryPipelineTerminal: Equatable, Sendable {
    case accepted(AcceptedTranscript)
    case failed(IOSFailedHistoryRetryPipelineFailure)
    case authorizationUnavailable
}

/// Provider-only C4.4B pipeline. It owns ordering and normalized outcomes but
/// no durable Store mutation; the coordinator consumes its terminal result
/// with the exact provider-completion claim.
struct IOSFailedHistoryRetryPipeline: Sendable {
    private let provider: any IOSFailedHistoryRetryProviderExecuting
    private let usageRecorder: any IOSFailedHistoryRetryUsageRecording
    private let timeouts: IOSFailedHistoryRetryProviderTimeouts
    private let timeoutSleeper: any IOSFailedHistoryRetryTimeoutSleeping
    private let postProcessor: TranscriptTextPostProcessor

    init(
        provider: any IOSFailedHistoryRetryProviderExecuting,
        usageRecorder: any IOSFailedHistoryRetryUsageRecording,
        timeouts: IOSFailedHistoryRetryProviderTimeouts = .defaults,
        timeoutSleeper: any IOSFailedHistoryRetryTimeoutSleeping =
            IOSFailedHistoryRetryContinuousClockSleeper(),
        postProcessor: TranscriptTextPostProcessor =
            TranscriptTextPostProcessor()
    ) {
        self.provider = provider
        self.usageRecorder = usageRecorder
        self.timeouts = timeouts
        self.timeoutSleeper = timeoutSleeper
        self.postProcessor = postProcessor
    }

    func run(
        _ invocation: IOSFailedHistoryRetryProviderInvocation
    ) async throws -> IOSFailedHistoryRetryPipelineTerminal {
        let setup = invocation.setup
        let transcriptionOutcome = try await runStage(
            timeout: timeouts.transcription
        ) {
            await provider.transcribe(
                IOSFailedHistoryRetryTranscriptionRequest(
                    transcriptionID: invocation.transcriptionID,
                    audio: invocation.audio,
                    resolvedModel:
                        setup.transcriptionConfiguration.resolvedModel,
                    resolvedLanguageCode:
                        setup.transcriptionConfiguration
                            .resolvedLanguageCode,
                    promptComposition:
                        setup.transcriptionPromptComposition,
                    timeout: timeouts.transcription
                )
            )
        }
        try Task.checkCancellation()

        let transcribed: AcceptedTranscript
        switch transcriptionOutcome {
        case .provider(.success(let text)):
            guard let accepted = try? AcceptedTranscript(rawText: text) else {
                return failure(.emptyResult, at: .transcription)
            }
            transcribed = accepted
        case .provider(.failure(.authorizationUnavailable)):
            return .authorizationUnavailable
        case .provider(.failure(let failure)):
            return self.failure(failure, at: .transcription)
        case .deadline:
            return failure(.timedOut, at: .transcription)
        }

        await recordUsage(
            transcriptionID: invocation.transcriptionID,
            setup: setup,
            audio: invocation.audio
        )
        try Task.checkCancellation()

        let corrected = try await correctedTranscript(
            transcribed,
            setup: setup
        )
        try Task.checkCancellation()

        let processedText = postProcessor.process(
            corrected.text,
            configuration: setup.postProcessingConfiguration,
            fallback: corrected.text
        )
        guard let processed = try? AcceptedTranscript(
            rawText: processedText
        ) else {
            return failure(.unknown, at: .transcription)
        }

        switch invocation.outputIntent {
        case .standard:
            guard setup.translationConfiguration == nil else {
                return failure(.invalidTranslationRoute, at: .transcription)
            }
            return .accepted(processed)

        case .translate:
            guard let translation = setup.translationConfiguration,
                  translation.canRunAction else {
                return failure(.invalidTranslationRoute, at: .translation)
            }
            let translationOutcome = try await runStage(
                timeout: timeouts.translation
            ) {
                await provider.translate(
                    IOSFailedHistoryRetryTranslationRequest(
                        translationRequest: TextTranslationRequest(
                            acceptedTranscript: processed,
                            translationConfiguration: translation,
                            transcriptionConfiguration:
                                setup.transcriptionConfiguration
                        ),
                        timeout: timeouts.translation
                    )
                )
            }
            try Task.checkCancellation()

            switch translationOutcome {
            case .provider(.success(let text)):
                guard let accepted = try? AcceptedTranscript(
                    rawText: text
                ) else {
                    return failure(.emptyResult, at: .translation)
                }
                guard setup.postProcessingConfiguration
                    .localTextCleanupEnabled else {
                    return .accepted(accepted)
                }
                let normalized = TranscriptTextPostProcessor
                    .normalizedInformalTypography(
                        from: accepted.text,
                        fallback: accepted.text
                    )
                guard let final = try? AcceptedTranscript(
                    rawText: normalized
                ) else {
                    return failure(.emptyResult, at: .translation)
                }
                return .accepted(final)
            case .provider(.failure(.authorizationUnavailable)):
                return .authorizationUnavailable
            case .provider(.failure(let failure)):
                return self.failure(failure, at: .translation)
            case .deadline:
                return failure(.timedOut, at: .translation)
            }
        }
    }

    private func correctedTranscript(
        _ transcript: AcceptedTranscript,
        setup: IOSFailedHistoryRetrySetupSnapshot
    ) async throws -> AcceptedTranscript {
        guard setup.textCorrectionConfiguration.isEnabled else {
            return transcript
        }
        let outcome = try await runStage(timeout: timeouts.correction) {
            await provider.correct(
                IOSFailedHistoryRetryCorrectionRequest(
                    transcript: transcript,
                    configuration: setup.textCorrectionConfiguration,
                    timeout: timeouts.correction
                )
            )
        }
        try Task.checkCancellation()
        guard case .provider(.success(let text)) = outcome,
              Self.isSafeCorrection(
                  original: transcript.text,
                  corrected: text
              ),
              let accepted = try? AcceptedTranscript(rawText: text) else {
            return transcript
        }
        return accepted
    }

    private func recordUsage(
        transcriptionID: UUID,
        setup: IOSFailedHistoryRetrySetupSnapshot,
        audio: IOSPendingTranscriptionAudio
    ) async {
        guard let usage = try? SuccessfulTranscriptionUsage(
            transcriptionID: transcriptionID,
            model: setup.transcriptionConfiguration.resolvedModel,
            audioDuration:
                TimeInterval(audio.durationMilliseconds) / 1_000
        ) else {
            return
        }
        do {
            try await usageRecorder.recordRetryUsage(usage)
        } catch {
            // Usage is deliberately non-authoritative for provider and History.
        }
    }

    private func failure(
        _ runtimeFailure: IOSFailedHistoryRetryRuntimeFailure,
        at stage: IOSFailedHistoryPipelineStage
    ) -> IOSFailedHistoryRetryPipelineTerminal {
        .failed(
            IOSFailedHistoryRetryPipelineFailure(
                runtimeFailure: runtimeFailure,
                stage: stage
            )
        )
    }

    private func runStage(
        timeout: Duration,
        operation: @escaping @Sendable () async
            -> IOSFailedHistoryRetryProviderTextOutcome
    ) async throws -> IOSFailedHistoryRetryStageOutcome {
        let race = IOSFailedHistoryRetryStageRace()
        let providerTask = Task {
            let outcome = await operation()
            await race.resolve(.provider(outcome))
        }
        let timeoutSleeper = timeoutSleeper
        let timeoutTask = Task {
            do {
                try await timeoutSleeper.sleep(for: timeout)
                await race.resolve(.deadline)
            } catch {
                if !Task.isCancelled {
                    await race.resolve(.deadline)
                }
            }
        }

        return try await withTaskCancellationHandler {
            let resolution = await race.wait()
            switch resolution {
            case .provider(let outcome):
                timeoutTask.cancel()
                _ = await timeoutTask.result
                try Task.checkCancellation()
                return .provider(outcome)
            case .deadline:
                providerTask.cancel()
                _ = await providerTask.result
                timeoutTask.cancel()
                _ = await timeoutTask.result
                try Task.checkCancellation()
                return .deadline
            case .cancelled:
                providerTask.cancel()
                timeoutTask.cancel()
                _ = await providerTask.result
                _ = await timeoutTask.result
                throw CancellationError()
            }
        } onCancel: {
            providerTask.cancel()
            timeoutTask.cancel()
            Task {
                await race.resolve(.cancelled)
            }
        }
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

extension IOSFailedHistoryRetryPipeline:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSFailedHistoryRetryPipeline(redacted)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

private enum IOSFailedHistoryRetryStageOutcome: Sendable {
    case provider(IOSFailedHistoryRetryProviderTextOutcome)
    case deadline
}

private actor IOSFailedHistoryRetryStageRace {
    enum Resolution: Sendable {
        case provider(IOSFailedHistoryRetryProviderTextOutcome)
        case deadline
        case cancelled
    }

    private var resolution: Resolution?
    private var continuation: CheckedContinuation<Resolution, Never>?

    func resolve(_ candidate: Resolution) {
        guard resolution == nil else { return }
        resolution = candidate
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: candidate)
    }

    func wait() async -> Resolution {
        if let resolution { return resolution }
        return await withCheckedContinuation { continuation in
            if let resolution {
                continuation.resume(returning: resolution)
            } else {
                self.continuation = continuation
            }
        }
    }
}

private protocol IOSFailedHistoryRetryRedactedValue {}

extension IOSFailedHistoryRetryRuntimeFailure:
    IOSFailedHistoryRetryRedactedValue {}
extension IOSFailedHistoryRetryProviderTextOutcome:
    IOSFailedHistoryRetryRedactedValue {}
extension IOSFailedHistoryRetryTranscriptionRequest:
    IOSFailedHistoryRetryRedactedValue {}
extension IOSFailedHistoryRetryCorrectionRequest:
    IOSFailedHistoryRetryRedactedValue {}
extension IOSFailedHistoryRetryTranslationRequest:
    IOSFailedHistoryRetryRedactedValue {}
extension IOSFailedHistoryRetryPipelineFailure:
    IOSFailedHistoryRetryRedactedValue {}
extension IOSFailedHistoryRetryPipelineTerminal:
    IOSFailedHistoryRetryRedactedValue {}

private extension IOSFailedHistoryRetryRedactedValue {
    var redactedDescription: String {
        "\(String(describing: type(of: self)))(redacted)"
    }
}

extension IOSFailedHistoryRetryRuntimeFailure:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { redactedDescription }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryProviderTextOutcome:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { redactedDescription }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryTranscriptionRequest:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { redactedDescription }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryCorrectionRequest:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { redactedDescription }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryTranslationRequest:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String { redactedDescription }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryPipelineFailure:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { redactedDescription }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSFailedHistoryRetryPipelineTerminal:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String { redactedDescription }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}
