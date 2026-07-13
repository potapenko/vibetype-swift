import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) @testable import HoldTypeIOSCore
import HoldTypeOpenAI
@_spi(HoldTypeIOSCore) @testable import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSForegroundVoiceProviderBridgeTests {
    @Test
    func missingCoordinatorKeepsGraphConstructibleAndUnavailable() async throws {
        let processor = BridgeProcessorCapture()
        let bridge = IOSForegroundVoiceProviderBridge(
            credentialClient: nil,
            processorClient: makeProcessorClient(processor)
        )

        guard case .unavailable = await bridge.resolveCredential() else {
            Issue.record("Expected unavailable credential resolution.")
            return
        }
        #expect(
            await bridge.revalidateCredential(
                IOSForegroundVoiceWorkflowCredentialProof()
            ) == false
        )

        let result = await bridge.process(
            try makeWorkflowRequest(
                credential: IOSForegroundVoiceWorkflowCredentialProof()
            ).request,
            progress: { _ in }
        )

        #expect(result == .notStarted(.credentialRejected))
        #expect(await processor.processCallCount() == 0)

    }

    @Test
    func confirmedAbsenceMapsToNeedsSetup() async {
        let credentials = BridgeCredentialSource(state: .notConfigured)
        let bridge = IOSForegroundVoiceProviderBridge(
            credentialClient: makeCredentialClient(credentials),
            processorClient: nil
        )

        guard case .needsSetup = await bridge.resolveCredential() else {
            Issue.record("Expected OpenAI setup requirement.")
            return
        }
        #expect(await credentials.resolveCallCount() == 1)
    }

    @Test
    func revalidationRequiresTheExactCurrentGeneration() async throws {
        let credentialA = try makeCredential(
            key: "bridge-revalidate-a",
            generation: UUID()
        )
        let credentialB = try makeCredential(
            key: "bridge-revalidate-b",
            generation: UUID()
        )
        let credentials = BridgeCredentialSource(state: .available(credentialA))
        let bridge = IOSForegroundVoiceProviderBridge(
            credentialClient: makeCredentialClient(credentials),
            processorClient: nil
        )
        let proof = try requireProof(await bridge.resolveCredential())

        #expect(await bridge.revalidateCredential(proof))
        await credentials.setState(.available(credentialB))
        #expect(await bridge.revalidateCredential(proof) == false)
        #expect(await bridge.revalidateCredential(proof) == false)
        #expect(await credentials.resolveCallCount() == 3)
    }

    @Test
    func replacementFromAToBRejectsAProofBeforeProviderCall() async throws {
        let credentialA = try makeCredential(
            key: "bridge-secret-a",
            generation: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        )
        let credentialB = try makeCredential(
            key: "bridge-secret-b",
            generation: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        )
        let credentials = BridgeCredentialSource(state: .available(credentialA))
        let processor = BridgeProcessorCapture()
        let bridge = IOSForegroundVoiceProviderBridge(
            credentialClient: makeCredentialClient(credentials),
            processorClient: makeProcessorClient(processor)
        )
        let proofA = try requireProof(await bridge.resolveCredential())
        await credentials.setState(.available(credentialB))

        let rejected = await bridge.process(
            try makeWorkflowRequest(credential: proofA).request,
            progress: { _ in }
        )

        #expect(rejected == .notStarted(.credentialRejected))
        #expect(await processor.processCallCount() == 0)

        let proofB = try requireProof(await bridge.resolveCredential())
        _ = await bridge.process(
            try makeWorkflowRequest(credential: proofB).request,
            progress: { _ in }
        )

        #expect(await processor.processCallCount() == 1)
        #expect(await processor.lastProcessCredential() == credentialB)
    }

    @Test
    func removalRejectsIssuedProofBeforeProviderCall() async throws {
        let credential = try makeCredential(
            key: "bridge-removal-canary",
            generation: UUID()
        )
        let credentials = BridgeCredentialSource(state: .available(credential))
        let processor = BridgeProcessorCapture()
        let bridge = IOSForegroundVoiceProviderBridge(
            credentialClient: makeCredentialClient(credentials),
            processorClient: makeProcessorClient(processor)
        )
        let proof = try requireProof(await bridge.resolveCredential())
        await credentials.setState(.notConfigured)

        let result = await bridge.process(
            try makeWorkflowRequest(credential: proof).request,
            progress: { _ in }
        )

        #expect(result == .notStarted(.credentialRejected))
        #expect(await processor.processCallCount() == 0)
    }

    @Test
    func newlyIssuedProofMakesPriorProofStaleEvenForSameGeneration()
        async throws {
        let credential = try makeCredential(
            key: "bridge-stale-canary",
            generation: UUID()
        )
        let credentials = BridgeCredentialSource(state: .available(credential))
        let processor = BridgeProcessorCapture()
        let bridge = IOSForegroundVoiceProviderBridge(
            credentialClient: makeCredentialClient(credentials),
            processorClient: makeProcessorClient(processor)
        )
        let staleProof = try requireProof(await bridge.resolveCredential())
        let currentProof = try requireProof(await bridge.resolveCredential())

        #expect(
            await bridge.process(
                try makeWorkflowRequest(credential: staleProof).request,
                progress: { _ in }
            ) == .notStarted(.credentialRejected)
        )
        #expect(await processor.processCallCount() == 0)

        _ = await bridge.process(
            try makeWorkflowRequest(credential: currentProof).request,
            progress: { _ in }
        )
        #expect(await processor.processCallCount() == 1)

        #expect(
            await bridge.process(
                try makeWorkflowRequest(credential: currentProof).request,
                progress: { _ in }
            ) == .notStarted(.credentialRejected)
        )
        #expect(await processor.processCallCount() == 1)
    }

    @Test
    func processMaterializesCurrentCredentialAndMapsFrozenRequest()
        async throws {
        let credential = try makeCredential(
            key: "bridge-process-canary",
            generation: UUID()
        )
        let credentials = BridgeCredentialSource(state: .available(credential))
        let processor = BridgeProcessorCapture(processResult: .busy)
        let bridge = IOSForegroundVoiceProviderBridge(
            credentialClient: makeCredentialClient(credentials),
            processorClient: makeProcessorClient(processor)
        )
        let proof = try requireProof(await bridge.resolveCredential())
        let fixture = try makeWorkflowRequest(
            credential: proof,
            mode: .retry
        )

        let result = await bridge.process(
            fixture.request,
            progress: { _ in }
        )

        #expect(result == .busy)
        let mapped = try #require(await processor.lastProcessRequest())
        #expect(mapped.sessionID == fixture.request.sessionID)
        #expect(mapped.pendingRecording == fixture.pending)
        #expect(mapped.mode == .retry)
        #expect(mapped.settings == fixture.settings)
        #expect(mapped.library == fixture.library)
        #expect(mapped.credential == credential)
        #expect(mapped.consentObservation == fixture.consent)
        #expect(await credentials.resolveCallCount() == 2)
    }

    @Test
    func proofAndBridgeSurfacesAreRedacted() async throws {
        let canary = "bridge-reflection-secret"
        let credential = try makeCredential(key: canary, generation: UUID())
        let credentials = BridgeCredentialSource(state: .available(credential))
        let client = makeCredentialClient(credentials)
        let bridge = IOSForegroundVoiceProviderBridge(
            credentialClient: client,
            processorClient: nil
        )
        let proof = try requireProof(await bridge.resolveCredential())

        for value in [String(describing: proof), String(reflecting: proof)] {
            #expect(value.contains(canary) == false)
            #expect(value.contains("redacted"))
        }
        #expect(Mirror(reflecting: proof).children.isEmpty)
        #expect(Mirror(reflecting: client).children.isEmpty)
        #expect(Mirror(reflecting: bridge).children.isEmpty)
        #expect(String(reflecting: bridge).contains(canary) == false)
    }

    @Test
    func noActiveHistoryPlaybackArbitratorCompletesHandoff() async {
        let arbitrator: any IOSForegroundVoiceHistoryPlaybackArbitrating =
            IOSNoActiveHistoryPlaybackArbitrator()

        #expect(await arbitrator.stopAndDeactivate())
    }
}

private enum BridgeCredentialState: Sendable {
    case available(IOSResolvedOpenAICredential)
    case notConfigured
    case unavailable
}

private enum BridgeTestError: Error {
    case unavailable
    case missingProof
}

private actor BridgeCredentialSource {
    private var state: BridgeCredentialState
    private var callCount = 0

    init(state: BridgeCredentialState) {
        self.state = state
    }

    func setState(_ state: BridgeCredentialState) {
        self.state = state
    }

    func resolve() throws -> IOSOpenAICredentialResolutionOutcome {
        callCount += 1
        switch state {
        case .available(let credential):
            return credentialOutcome(.available(credential))
        case .notConfigured:
            return credentialOutcome(.notConfigured)
        case .unavailable:
            throw BridgeTestError.unavailable
        }
    }

    func resolveCallCount() -> Int { callCount }
}

private actor BridgeProcessorCapture {
    private let processResult: IOSForegroundVoiceProcessingResolution
    private var processRequests: [IOSForegroundVoiceProcessingRequest] = []

    init(
        processResult: IOSForegroundVoiceProcessingResolution =
            .notStarted(.networkFailure)
    ) {
        self.processResult = processResult
    }

    func process(
        _ request: IOSForegroundVoiceProcessingRequest
    ) -> IOSForegroundVoiceProcessingResolution {
        processRequests.append(request)
        return processResult
    }

    func processCallCount() -> Int { processRequests.count }
    func lastProcessRequest() -> IOSForegroundVoiceProcessingRequest? {
        processRequests.last
    }
    func lastProcessCredential() -> IOSResolvedOpenAICredential? {
        processRequests.last?.credential
    }
}

private struct BridgeWorkflowRequestFixture {
    let request: IOSForegroundVoiceWorkflowProcessingRequest
    let pending: IOSV1PendingRecording
    let settings: IOSAppSettings
    let library: IOSLibraryContent
    let consent: IOSV1ProviderConsentObservation
}

private func makeCredentialClient(
    _ source: BridgeCredentialSource
) -> IOSForegroundVoiceCredentialClient {
    IOSForegroundVoiceCredentialClient {
        try await source.resolve()
    }
}

private func makeProcessorClient(
    _ capture: BridgeProcessorCapture
) -> IOSForegroundVoiceCoreProcessorClient {
    IOSForegroundVoiceCoreProcessorClient(
        process: { request, _ in
            await capture.process(request)
        }
    )
}

private func makeCredential(
    key: String,
    generation: UUID
) throws -> IOSResolvedOpenAICredential {
    IOSResolvedOpenAICredential(
        credential: try OpenAICredential(apiKey: key),
        generation: IOSOpenAICredentialGeneration(rawValue: generation)
    )
}

private func credentialOutcome(
    _ resolution: IOSOpenAICredentialResolution
) -> IOSOpenAICredentialResolutionOutcome {
    let primary: IOSOpenAICredentialPrimaryStatus
    switch resolution {
    case .available:
        primary = .availableInThisProcess
    case .notConfigured:
        primary = .notConfigured
    }
    return IOSOpenAICredentialResolutionOutcome(
        resolution: resolution,
        status: IOSOpenAICredentialStatus(
            primary: primary,
            statusNeedsRefresh: false,
            localMarkerIssue: nil
        )
    )
}

private func requireProof(
    _ resolution: IOSForegroundVoiceWorkflowCredentialResolution
) throws -> IOSForegroundVoiceWorkflowCredentialProof {
    guard case .available(let proof) = resolution else {
        throw BridgeTestError.missingProof
    }
    return proof
}

private func makeWorkflowRequest(
    credential: IOSForegroundVoiceWorkflowCredentialProof,
    mode: IOSForegroundVoiceProcessingMode = .initial
) throws -> BridgeWorkflowRequestFixture {
    let settings = IOSAppSettings.defaults
    let library = IOSLibraryContent.defaults
    let pending = try makeBridgePendingRecording(
        configuration: settings.transcriptionConfiguration
    )
    let consent = makeConsentObservation()
    return BridgeWorkflowRequestFixture(
        request: IOSForegroundVoiceWorkflowProcessingRequest(
            sessionID: UUID(),
            pendingRecording: pending,
            mode: mode,
            configuration: IOSForegroundVoiceWorkflowConfiguration(
                settings: settings,
                library: library
            ),
            credential: credential,
            consentObservation: consent
        ),
        pending: pending,
        settings: settings,
        library: library,
        consent: consent
    )
}

private func makeConsentObservation() -> IOSV1ProviderConsentObservation {
    IOSV1ProviderConsentQualificationFixture.acceptedObservation()
}

private func makeBridgePendingRecording(
    configuration: TranscriptionConfiguration
) throws -> IOSV1PendingRecording {
    let attemptID = UUID()
    let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
    let state = try IOSVoiceStatePending(
        attemptID: attemptID,
        audioRelativeIdentifier:
            IOSVoiceStateStorageLocation.relativeAudioIdentifier(
                for: attemptID
            ),
        createdAt: createdAt,
        updatedAt: createdAt,
        outputIntent: .standard,
        transcriptionModel: configuration.resolvedModel,
        transcriptionLanguageCode: configuration.resolvedLanguageCode,
        durationMilliseconds: 1_000,
        byteCount: 1_024,
        status: .ready
    )
    return IOSV1PendingRecording(state)
}
