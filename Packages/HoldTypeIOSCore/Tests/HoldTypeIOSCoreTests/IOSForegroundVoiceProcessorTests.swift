import Foundation
import HoldTypeDomain
import HoldTypeOpenAI
@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@_spi(HoldTypeIOSCore) @testable import HoldTypeIOSCore

@MainActor
@Suite(.serialized)
struct IOSForegroundVoiceProcessorTests {
    @Test func standardFlowTransformsTextAndCommitsLatest() async throws {
        var settings = IOSAppSettings.defaults
        settings.localTextCleanupEnabled = true
        let fixture = try await ProcessorFixture(
            settings: settings,
            library: IOSLibraryContent(
                replacementRules: [
                    TextReplacementRule(
                        search: "voice",
                        replacement: "world"
                    ),
                ]
            )
        )
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let usage = ProcessorUsageCapture()
        let progress = ProcessorProgressCapture()
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { request, _ in
                    calls.record("transcription")
                    #expect(request.model == fixture.pending.transcriptionModel)
                    return "Hello voice"
                }
            ),
            usageCapture: usage
        )

        let result = await processor.process(
            fixture.request(),
            progress: { progress.record($0) }
        )
        let record = try result.requireReady()

        #expect(record.acceptedText == "Hello world")
        #expect(record.sourceAttemptID == fixture.pending.attemptID)
        #expect(calls.events == ["transcription"])
        #expect(usage.values.count == 1)
        #expect(
            usage.values.first?.transcriptionID
                != fixture.pending.transcriptionID
        )
        #expect(try await fixture.persistenceOwner.load() == nil)
        guard case .resultReady(let latest) =
            try await fixture.persistenceOwner.loadLatestResult() else {
            Issue.record("Expected Latest Result after acceptance.")
            return
        }
        #expect(latest.resultID == record.resultID)
        #expect(latest.sourceAttemptID == record.sourceAttemptID)
        #expect(latest.acceptedText == record.acceptedText)
        let history = try await IOSAcceptedTextHistoryRepository(
            applicationSupportDirectoryURL: fixture.root
        ).load()
        #expect(history.entries.count == 1)
        #expect(history.entries.first?.resultID == record.resultID)
        #expect(history.entries.first?.text == record.acceptedText)
        #expect(
            progress.stages
                == [.transcription, .postProcessing, .outputDelivery]
        )
    }

    @Test func providerFailurePersistsFailedAndOnlyExplicitRetryReplays()
        async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        let providerSequence = ProcessorTranscriptionSequence(
            outcomes: [
                .failure(.networkUnavailable),
                .success("Explicit retry result"),
            ]
        )
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { request, _ in
                    try providerSequence.next(model: request.model)
                }
            )
        )

        guard case .retryAvailable(
            let failed,
            failure: .networkUnavailable,
            stage: .transcription
        ) = await processor.process(fixture.request()) else {
            Issue.record("Expected one durable failed Pending.")
            return
        }
        #expect(failed.phase == .failed)
        #expect(failed.transcriptionID == nil)
        #expect(providerSequence.callCount == 1)

        // Constructing another processor and observing durable state performs
        // no provider work. Only the explicit request below is allowed to run.
        _ = fixture.makeProcessor(
            provider: provider(
                transcribe: { request, _ in
                    try providerSequence.next(model: request.model)
                }
            )
        )
        #expect(try await fixture.persistenceOwner.load()?.recording == failed)
        #expect(providerSequence.callCount == 1)

        var retrySettings = fixture.settings
        retrySettings.transcriptionConfiguration =
            TranscriptionConfiguration(
                model: "current-retry-model",
                language: .russian
            )
        let record = try await processor.process(
            fixture.request(
                pendingRecording: failed,
                mode: .retry,
                settings: retrySettings
            )
        ).requireReady()

        #expect(record.acceptedText == "Explicit retry result")
        #expect(providerSequence.callCount == 2)
        #expect(
            providerSequence.models
                == [fixture.pending.transcriptionModel, "current-retry-model"]
        )
    }

    @Test func correctionFailureIsFailOpenAndCredentialRejectionIsRecorded()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.textCorrectionConfiguration.isEnabled = true
        let fixture = try await ProcessorFixture(settings: settings)
        defer { fixture.removeFiles() }
        let rejected = ProcessorGenerationCapture()
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in "Original transcript" },
                correct: { _, _, _ in
                    throw OpenAITextCorrectionServiceError.invalidAPIKey
                }
            ),
            rejectionCapture: rejected
        )

        let record = try await processor.process(
            fixture.request()
        ).requireReady()

        #expect(record.acceptedText == "Original transcript")
        #expect(rejected.values == [fixture.credential.generation])
    }

    @Test func translationFailurePersistsFailedForExplicitRetry()
        async throws {
        var settings = IOSAppSettings.defaults
        settings.translationConfiguration = TranslationConfiguration(
            actionPreferenceEnabled: true,
            targetLanguage: .french
        )
        let fixture = try await ProcessorFixture(
            outputIntent: .translate,
            settings: settings
        )
        defer { fixture.removeFiles() }
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in "Translate me" },
                translate: { _, _ in
                    throw OpenAITextTranslationServiceError.timedOut
                }
            )
        )

        guard case .retryAvailable(
            let failed,
            failure: .timedOut,
            stage: .postProcessing
        ) = await processor.process(fixture.request()) else {
            Issue.record("Expected failed Pending after Translation failure.")
            return
        }
        #expect(failed.phase == .failed)
        #expect(try await fixture.persistenceOwner.load()?.recording == failed)
        #expect(
            try await fixture.persistenceOwner.loadLatestResult() == .absent
        )
    }

    @Test func acceptanceCommitUncertaintyReconcilesWithoutProviderReplay()
        async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        let persistence = CommitThenThrowPersistence(
            base: fixture.persistenceOwner
        )
        let calls = ProcessorCallLog()
        let processor = fixture.makeProcessor(
            persistence: persistence,
            provider: provider(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "Committed once"
                }
            )
        )

        let record = try await processor.process(
            fixture.request()
        ).requireReady()

        #expect(record.acceptedText == "Committed once")
        #expect(calls.events == ["transcription"])
        #expect(persistence.acceptCallCount == 1)
        #expect(persistence.reconcileCallCount == 1)
        #expect(try await fixture.persistenceOwner.load() == nil)
    }

    @Test func invalidInitialConfigurationNeverStartsProvider() async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        let calls = ProcessorCallLog()
        let processor = fixture.makeProcessor(
            provider: provider(
                transcribe: { _, _ in
                    calls.record("transcription")
                    return "unexpected"
                }
            )
        )

        var mismatchingSettings = fixture.settings
        mismatchingSettings.transcriptionConfiguration =
            TranscriptionConfiguration(model: "mismatching-model")
        #expect(
            await processor.process(
                fixture.request(settings: mismatchingSettings)
            ) == .notStarted(.invalidConfiguration)
        )
        #expect(calls.events.isEmpty)
        #expect(
            try await fixture.persistenceOwner.load()?.recording
                == fixture.pending
        )
    }

    @Test func diagnosticsRedactTextCredentialAndPaths() async throws {
        let fixture = try await ProcessorFixture()
        defer { fixture.removeFiles() }
        let request = fixture.request()
        let processor = fixture.makeProcessor(provider: provider())
        var dumpText = ""
        dump((request, processor), to: &dumpText)
        let diagnostics = [
            dumpText,
            String(describing: request),
            String(reflecting: request),
            String(describing: processor),
            String(reflecting: processor),
        ].joined(separator: "\n")

        #expect(
            diagnostics.contains(
                "IOSForegroundVoiceProcessingRequest(redacted)"
            )
        )
        #expect(diagnostics.contains("IOSForegroundVoiceProcessor(redacted)"))
        for canary in ["sk-processor-test", fixture.root.path] {
            #expect(!diagnostics.contains(canary))
        }
    }
}

private final class ProcessorFixture: @unchecked Sendable {
    let root: URL
    let persistenceOwner: IOSV1ForegroundVoicePersistenceOwner
    let consentCoordinator: IOSV1ProviderConsentCoordinator
    let acceptedConsent: IOSV1ProviderConsentObservation
    let pending: IOSV1PendingRecording
    let settings: IOSAppSettings
    let library: IOSLibraryContent
    let credential: IOSResolvedOpenAICredential

    init(
        outputIntent: DictationOutputIntent = .standard,
        settings: IOSAppSettings = .defaults,
        library: IOSLibraryContent = .defaults
    ) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ios-v1-foreground-processor-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        self.settings = settings
        self.library = library
        persistenceOwner = IOSV1ForegroundVoicePersistenceOwner(
            applicationSupportDirectoryURL: root
        )

        let attemptID = UUID()
        let audio = try makeForegroundVoiceTestM4A(durationSeconds: 3)
        let lease = try await persistenceOwner.createCapture(
            attemptID: attemptID,
            outputIntent: outputIntent
        )
        try lease.withTransientRecordingURL { url in
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: audio)
            try handle.close()
        }
        try lease.revalidateRecorderCheckpoint()
        try await lease.beginFinalizing()
        guard case .completed(let completed) =
            try await lease.completeAfterRecorderClose() else {
            throw ProcessorFixtureError.invalidCapture
        }
        _ = try await persistenceOwner.prepareCompletedCapture(
            completed,
            transcriptionConfiguration: settings.transcriptionConfiguration
        )
        guard let prepared = try await persistenceOwner.load()?.recording else {
            throw ProcessorFixtureError.invalidCapture
        }
        pending = prepared

        consentCoordinator = IOSV1ProviderConsentCoordinator(
            applicationSupportDirectoryURL: root
        )
        acceptedConsent = try await consentCoordinator.accept(
            using: await consentCoordinator.observe(),
            decisionAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        credential = IOSResolvedOpenAICredential(
            credential: try OpenAICredential(apiKey: "sk-processor-test"),
            generation: IOSOpenAICredentialGeneration(rawValue: UUID())
        )
    }

    func request(
        pendingRecording: IOSV1PendingRecording? = nil,
        mode: IOSForegroundVoiceProcessingMode = .initial,
        settings: IOSAppSettings? = nil
    ) -> IOSForegroundVoiceProcessingRequest {
        IOSForegroundVoiceProcessingRequest(
            sessionID: UUID(),
            pendingRecording: pendingRecording ?? pending,
            mode: mode,
            settings: settings ?? self.settings,
            library: library,
            credential: credential,
            consentObservation: acceptedConsent
        )
    }

    func makeProcessor(
        persistence: (any IOSForegroundVoicePersisting)? = nil,
        provider: IOSForegroundVoiceOpenAIProviderOperations,
        usageCapture: ProcessorUsageCapture? = nil,
        rejectionCapture: ProcessorGenerationCapture? = nil
    ) -> IOSForegroundVoiceProcessor {
        let identifiers = ProcessorUUIDSequence()
        return IOSForegroundVoiceProcessor(
            persistenceOwner: persistence ?? persistenceOwner,
            consentCoordinator: consentCoordinator,
            provider: provider,
            recordUsage: { usage in usageCapture?.record(usage) },
            recordProviderRejection: { generation in
                rejectionCapture?.record(generation)
            },
            makeUUID: { identifiers.next() }
        )
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class CommitThenThrowPersistence:
    IOSForegroundVoicePersisting,
    @unchecked Sendable {
    private let base: IOSV1ForegroundVoicePersistenceOwner
    private let lock = NSLock()
    private var storedAcceptCallCount = 0
    private var storedReconcileCallCount = 0

    init(base: IOSV1ForegroundVoicePersistenceOwner) {
        self.base = base
    }

    var acceptCallCount: Int { lock.withLock { storedAcceptCallCount } }
    var reconcileCallCount: Int { lock.withLock { storedReconcileCallCount } }

    func load() async throws -> IOSV1PendingRecordingObservation? {
        try await base.load()
    }

    func beginTranscription(
        expected: IOSV1PendingRecordingExpectation,
        transcriptionID: UUID
    ) async throws -> IOSV1ForegroundVoiceTranscriptionDispatch {
        try await base.beginTranscription(
            expected: expected,
            transcriptionID: transcriptionID
        )
    }

    func retryTranscription(
        expected: IOSV1PendingRecordingExpectation,
        transcriptionID: UUID,
        transcriptionConfiguration: TranscriptionConfiguration
    ) async throws -> IOSV1ForegroundVoiceTranscriptionDispatch {
        try await base.retryTranscription(
            expected: expected,
            transcriptionID: transcriptionID,
            transcriptionConfiguration: transcriptionConfiguration
        )
    }

    func markPostProcessing(
        expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecording {
        try await base.markPostProcessing(expected: expected)
    }

    func markOutputDelivery(
        expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecording {
        try await base.markOutputDelivery(expected: expected)
    }

    func markFailed(
        expected: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1PendingRecording {
        try await base.markFailed(expected: expected)
    }

    func accept(
        _ preparation: IOSV1ForegroundVoiceAcceptedOutputPreparation,
        expectedPending: IOSV1PendingRecordingExpectation
    ) async throws -> IOSV1ForegroundVoiceAcceptanceResult {
        lock.withLock { storedAcceptCallCount += 1 }
        _ = try await base.accept(
            preparation,
            expectedPending: expectedPending
        )
        throw ProcessorFixtureError.injectedFailure
    }

    func reconcileAcceptance(
        matching preparation: IOSV1ForegroundVoiceAcceptedOutputPreparation
    ) async throws -> IOSV1ForegroundVoiceAcceptanceResult? {
        lock.withLock { storedReconcileCallCount += 1 }
        return try await base.reconcileAcceptance(matching: preparation)
    }
}

private func provider(
    transcribe: @escaping IOSForegroundVoiceOpenAIProviderOperations.Transcribe = {
        _, _ in "Transcript"
    },
    correct: @escaping IOSForegroundVoiceOpenAIProviderOperations.Correct = {
        transcript, _, _ in transcript.text
    },
    translate: @escaping IOSForegroundVoiceOpenAIProviderOperations.Translate = {
        _, _ in "Translated"
    }
) -> IOSForegroundVoiceOpenAIProviderOperations {
    IOSForegroundVoiceOpenAIProviderOperations(
        transcribe: transcribe,
        correct: correct,
        translate: translate
    )
}

private final class ProcessorCallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []

    var events: [String] { lock.withLock { storedEvents } }
    func record(_ event: String) {
        lock.withLock { storedEvents.append(event) }
    }
}

private final class ProcessorUsageCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [SuccessfulTranscriptionUsage] = []

    var values: [SuccessfulTranscriptionUsage] {
        lock.withLock { storedValues }
    }
    func record(_ value: SuccessfulTranscriptionUsage) {
        lock.withLock { storedValues.append(value) }
    }
}

private final class ProcessorGenerationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [IOSOpenAICredentialGeneration] = []

    var values: [IOSOpenAICredentialGeneration] {
        lock.withLock { storedValues }
    }
    func record(_ value: IOSOpenAICredentialGeneration) {
        lock.withLock { storedValues.append(value) }
    }
}

@MainActor
private final class ProcessorProgressCapture {
    private(set) var stages: [VoiceAttemptStage] = []
    func record(_ stage: VoiceAttemptStage) { stages.append(stage) }
}

private final class ProcessorTranscriptionSequence: @unchecked Sendable {
    enum Outcome {
        case success(String)
        case failure(OpenAITranscriptionServiceError)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]
    private var storedModels: [String] = []

    init(outcomes: [Outcome]) { self.outcomes = outcomes }

    var callCount: Int { lock.withLock { storedModels.count } }
    var models: [String] { lock.withLock { storedModels } }

    func next(model: String) throws -> String {
        let outcome = lock.withLock { () -> Outcome in
            storedModels.append(model)
            return outcomes.removeFirst()
        }
        switch outcome {
        case .success(let text): return text
        case .failure(let error): throw error
        }
    }
}

private final class ProcessorUUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt8 = 1

    func next() -> UUID {
        lock.withLock {
            defer { counter &+= 1 }
            return UUID(
                uuid: (
                    counter, 0, 0, 0, 0, 0x40, 0x40, 0x40,
                    0x80, 0, 0, 0, 0, 0, 0, counter
                )
            )
        }
    }
}

private enum ProcessorFixtureError: Error {
    case invalidCapture
    case injectedFailure
}

private extension IOSForegroundVoiceProcessingResolution {
    func requireReady() throws -> IOSV1AcceptedOutputDeliveryRecord {
        guard case .acceptance(.resultReady(let record, _)) = self else {
            throw ProcessorFixtureError.injectedFailure
        }
        return record
    }
}
