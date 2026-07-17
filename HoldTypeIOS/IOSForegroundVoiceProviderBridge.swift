import Foundation
import HoldTypeDomain
@_spi(HoldTypeIOSCore) import HoldTypeIOSCore
@_spi(HoldTypeIOSCore) import HoldTypePersistence

/// Narrow credential resolver used by the process Voice bridge. Its production
/// closure captures the one composition-owned coordinator, but reflection can
/// never traverse that capture or a resolved key.
nonisolated struct IOSForegroundVoiceCredentialClient: Sendable {
    typealias Resolve = @Sendable () async throws ->
        IOSOpenAICredentialResolutionOutcome

    let resolveVoicePreflight: Resolve

    init(coordinator: IOSOpenAICredentialCoordinator) {
        resolveVoicePreflight = {
            try await coordinator.resolve(for: .voicePreflight)
        }
    }

    init(resolveVoicePreflight: @escaping Resolve) {
        self.resolveVoicePreflight = resolveVoicePreflight
    }
}

/// Narrow Core processor boundary. Keeping these closures together lets the
/// Voice graph remain constructible when its production processor is absent.
nonisolated struct IOSForegroundVoiceCoreProcessorClient: Sendable {
    typealias Process = @Sendable (
        IOSForegroundVoiceProcessingRequest,
        @escaping IOSForegroundVoiceProcessingProgressHandler
    ) async -> IOSForegroundVoiceProcessingResolution

    let process: Process

    init(processor: IOSForegroundVoiceProcessor) {
        process = { request, progress in
            await processor.process(request, progress: progress)
        }
    }

    init(process: @escaping Process) {
        self.process = process
    }
}

/// Process-owned capability bridge between the Voice workflow and Core.
///
/// It retains only one opaque proof and its redacted credential generation.
/// The resolved credential exists only in the stack frame that immediately
/// maps a current workflow request into a Core call.
actor IOSForegroundVoiceProviderBridge {
    private struct ProofRecord: Sendable {
        let proof: IOSForegroundVoiceWorkflowCredentialProof
        let generation: IOSOpenAICredentialGeneration
    }

    private let credentialClient: IOSForegroundVoiceCredentialClient?
    private let processorClient: IOSForegroundVoiceCoreProcessorClient?
    private var activeProof: ProofRecord?

    init(
        credentialCoordinator: IOSOpenAICredentialCoordinator?,
        processor: IOSForegroundVoiceProcessor?
    ) {
        credentialClient = credentialCoordinator.map(
            IOSForegroundVoiceCredentialClient.init(coordinator:)
        )
        processorClient = processor.map(
            IOSForegroundVoiceCoreProcessorClient.init(processor:)
        )
    }

    init(
        credentialClient: IOSForegroundVoiceCredentialClient?,
        processorClient: IOSForegroundVoiceCoreProcessorClient?
    ) {
        self.credentialClient = credentialClient
        self.processorClient = processorClient
    }

    func resolveCredential()
        async -> IOSForegroundVoiceWorkflowCredentialResolution {
        guard let credentialClient else {
            activeProof = nil
            return .unavailable
        }

        do {
            let outcome = try await credentialClient.resolveVoicePreflight()
            switch outcome.resolution {
            case .available(let resolved):
                let proof = IOSForegroundVoiceWorkflowCredentialProof()
                activeProof = ProofRecord(
                    proof: proof,
                    generation: resolved.generation
                )
                return .available(proof)
            case .notConfigured:
                activeProof = nil
                return .needsSetup
            }
        } catch {
            activeProof = nil
            return .unavailable
        }
    }

    func revalidateCredential(
        _ proof: IOSForegroundVoiceWorkflowCredentialProof
    ) async -> Bool {
        guard let expected = activeProof,
              expected.proof == proof,
              let credentialClient else {
            return false
        }

        do {
            let outcome = try await credentialClient.resolveVoicePreflight()
            guard let current = activeProof,
                  current.proof == proof,
                  current.generation == expected.generation,
                  case .available(let resolved) = outcome.resolution,
                  resolved.generation == expected.generation else {
                retire(proof)
                return false
            }
            return true
        } catch {
            retire(proof)
            return false
        }
    }

    func process(
        _ request: IOSForegroundVoiceWorkflowProcessingRequest,
        progress: @escaping IOSForegroundVoiceProcessingProgressHandler
    ) async -> IOSForegroundVoiceProcessingResolution {
        guard let processorClient else {
            if let credential = request.credential { retire(credential) }
            return .notStarted(.providerUnavailable)
        }
        let credential: IOSResolvedOpenAICredential?
        if let proof = request.credential {
            guard let resolved = await consumeCredential(for: proof) else {
                return .notStarted(.credentialRejected)
            }
            credential = resolved
        } else {
            credential = nil
        }

        return await processorClient.process(
            IOSForegroundVoiceProcessingRequest(
                sessionID: request.sessionID,
                pendingRecording: request.pendingRecording,
                mode: request.mode,
                settings: request.configuration.settings,
                library: request.configuration.library,
                credential: credential,
                consentObservation: request.consentObservation,
                forcesTextCorrection: request.forcesTextCorrection,
                cancellationAuthority: request.cancellationAuthority
            ),
            progress
        )
    }

    private func consumeCredential(
        for proof: IOSForegroundVoiceWorkflowCredentialProof
    ) async -> IOSResolvedOpenAICredential? {
        guard let expected = activeProof,
              expected.proof == proof,
              let credentialClient else {
            return nil
        }

        // Consume before suspension so concurrent calls cannot reuse the proof.
        activeProof = nil
        do {
            let outcome = try await credentialClient.resolveVoicePreflight()
            guard case .available(let resolved) = outcome.resolution,
                  resolved.generation == expected.generation else {
                return nil
            }
            return resolved
        } catch {
            return nil
        }
    }

    private func retire(
        _ proof: IOSForegroundVoiceWorkflowCredentialProof
    ) {
        guard activeProof?.proof == proof else { return }
        activeProof = nil
    }
}

/// History playback remains an explicit process boundary before Voice audio
/// activation even while no playback UI exists.
protocol IOSForegroundVoiceHistoryPlaybackArbitrating: Sendable {
    func stopAndDeactivate() async -> Bool
}

nonisolated struct IOSNoActiveHistoryPlaybackArbitrator:
    IOSForegroundVoiceHistoryPlaybackArbitrating {
    func stopAndDeactivate() async -> Bool { true }
}

extension IOSForegroundVoiceCredentialClient:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoiceCredentialClient(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceCoreProcessorClient:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSForegroundVoiceCoreProcessorClient(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSForegroundVoiceProviderBridge:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSForegroundVoiceProviderBridge(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}
