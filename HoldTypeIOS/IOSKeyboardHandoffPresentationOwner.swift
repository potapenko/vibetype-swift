import Foundation
import Observation

/// Presentation-only owner for the temporary sheet over the unchanged Voice
/// screen. The session coordinator remains the sole keyboard workflow owner.
@MainActor
@Observable
final class IOSKeyboardHandoffPresentationOwner {
    private static let maximumStartAttemptCount = 8

    private(set) var presentation: IOSKeyboardHandoffSheetPresentation?

    @ObservationIgnored
    private let session: IOSKeyboardDictationSessionCoordinator
    @ObservationIgnored
    private let preflight: IOSKeyboardHandoffPreflightClient
    @ObservationIgnored
    private let pendingRecordingOwner:
        IOSPendingRecordingHistoryStateOwner?
    @ObservationIgnored
    private let waitBeforeStartRetry: @MainActor @Sendable () async -> Void
    private var activeRequestID: UUID?
    private var armingRequestID: UUID?
    private var generation: UInt64 = 0
    private var cancellationTask: Task<Void, Never>?

    init(
        session: IOSKeyboardDictationSessionCoordinator,
        preflight: IOSKeyboardHandoffPreflightClient = .passThrough(),
        pendingRecordingOwner:
            IOSPendingRecordingHistoryStateOwner? = nil,
        waitBeforeStartRetry: @escaping @MainActor @Sendable () async -> Void = {
            try? await Task.sleep(for: .milliseconds(150))
        }
    ) {
        self.session = session
        self.preflight = preflight
        self.pendingRecordingOwner = pendingRecordingOwner
        self.waitBeforeStartRetry = waitBeforeStartRetry
    }

    var savedRecordingOwner: IOSPendingRecordingHistoryStateOwner? {
        pendingRecordingOwner
    }

    func start(_ intent: KeyboardHandoffIntentRecord) async {
        // Listening owns a live, potentially non-empty recording. A fresh
        // launch only re-presents that exact attempt; it must not run preflight
        // or reach recorder supersession.
        if cancellationTask == nil,
           retainActiveListeningHandoffIfAvailable() {
            return
        }

        // Processing already owns a durable Pending transition. A fresh tap
        // may reveal that exact saved owner, but it never supersedes it.
        if session.presentation == .processing {
            await revealCurrentSavedRecordingIfAvailable()
            return
        }
        let previousRequestID = activeRequestID
        generation &+= 1
        let currentGeneration = generation
        activeRequestID = intent.requestID
        presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .starting
        )

        if await revealSavedRecordingIfAvailable(
            requestID: intent.requestID,
            generation: currentGeneration
        ) {
            return
        }
        guard generation == currentGeneration,
              activeRequestID == intent.requestID else {
            return
        }

        // A close from the previous sheet may still be waiting for recorder
        // cancellation. A fresh request supersedes its presentation
        // immediately, but does not race that cleanup inside the shared
        // keyboard session.
        await cancellationTask?.value
        if let previousRequestID,
           previousRequestID != intent.requestID {
            await session.interruptHandoffForSupersession(
                requestID: previousRequestID
            )
        }
        guard generation == currentGeneration,
              activeRequestID == intent.requestID else {
            return
        }

        let preflightResult = await preflight.run(intent)
        guard generation == currentGeneration,
              activeRequestID == intent.requestID else {
            return
        }
        if case .blocked(let issue) = preflightResult {
            presentation = IOSKeyboardHandoffSheetPresentation(issue: issue)
            return
        }

        armingRequestID = intent.requestID
        for startAttemptIndex in 0..<Self.maximumStartAttemptCount {
            if startAttemptIndex > 0 {
                await waitBeforeStartRetry()
            }
            guard generation == currentGeneration,
                  activeRequestID == intent.requestID else {
                return
            }

            let started = await session.startHandoff(intent) {
                [weak self] requestID, event in
                self?.receive(event, requestID: requestID)
            }
            guard generation == currentGeneration,
                  activeRequestID == intent.requestID else {
                return
            }
            if started {
                armingRequestID = nil
                return
            }
            if retainActiveListeningHandoffIfAvailable() {
                return
            }
            if await revealSavedRecordingIfAvailable(
                requestID: intent.requestID,
                generation: currentGeneration
            ) {
                return
            }
        }

        armingRequestID = nil
        activeRequestID = nil
        presentation = nil
    }

    func cancelFromSheet() {
        if presentation?.phase == .savedRecording {
            closeSavedRecordingPresentation()
            return
        }
        guard cancellationTask == nil,
              let requestID = activeRequestID else {
            return
        }
        cancellationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.cancel(requestID: requestID)
            self.cancellationTask = nil
        }
    }

    func savedRecordingDidResolve() {
        guard presentation?.phase == .savedRecording,
              pendingRecordingOwner?.isConfirmedAbsent == true else {
            return
        }
        closeSavedRecordingPresentation()
    }

    private func cancel(requestID: UUID) async {
        await session.cancelHandoff(requestID: requestID)
        guard activeRequestID == requestID else { return }
        generation &+= 1
        armingRequestID = nil
        activeRequestID = nil
        presentation = nil
    }

    private func receive(
        _ event: IOSKeyboardHandoffCaptureEvent,
        requestID: UUID
    ) {
        guard activeRequestID == requestID else { return }
        switch event {
        case .listening:
            presentation = IOSKeyboardHandoffSheetPresentation(
                phase: .listening
            )
        case .processing:
            presentation = IOSKeyboardHandoffSheetPresentation(
                phase: .processing
            )
        case .terminal(.completed), .terminal(.cancelled):
            activeRequestID = nil
            presentation = nil
        case .terminal(.failed), .terminal(.expired):
            guard armingRequestID != requestID else { return }
            let currentGeneration = generation
            Task { @MainActor [weak self] in
                guard let self else { return }
                let revealed = await self.revealSavedRecordingIfAvailable(
                    requestID: requestID,
                    generation: currentGeneration
                )
                guard self.generation == currentGeneration,
                      self.activeRequestID == requestID,
                      !revealed else {
                    return
                }
                self.activeRequestID = nil
                self.presentation = nil
            }
        }
    }

    private func retainActiveListeningHandoffIfAvailable() -> Bool {
        guard let requestID = session.observeActiveListeningHandoff({
            [weak self] requestID, event in
            self?.receive(event, requestID: requestID)
        }) else {
            return false
        }
        armingRequestID = nil
        activeRequestID = requestID
        presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .listening
        )
        return true
    }

    private func revealCurrentSavedRecordingIfAvailable() async {
        guard let pendingRecordingOwner else { return }
        let confirmed = await pendingRecordingOwner.refresh()
        guard pendingRecordingOwner.shouldPresentSavedRecording
                || (!confirmed
                    && !pendingRecordingOwner.isConfirmedAbsent) else {
            return
        }
        presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .savedRecording
        )
    }

    private func revealSavedRecordingIfAvailable(
        requestID: UUID,
        generation expectedGeneration: UInt64
    ) async -> Bool {
        guard let pendingRecordingOwner else { return false }
        let confirmed = await pendingRecordingOwner.refresh()
        guard generation == expectedGeneration,
              activeRequestID == requestID,
              pendingRecordingOwner.shouldPresentSavedRecording
                || (!confirmed
                    && !pendingRecordingOwner.isConfirmedAbsent) else {
            return false
        }
        armingRequestID = nil
        presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .savedRecording
        )
        return true
    }

    private func closeSavedRecordingPresentation() {
        generation &+= 1
        armingRequestID = nil
        activeRequestID = nil
        presentation = nil
        guard let pendingRecordingOwner else { return }
        Task { await pendingRecordingOwner.stopPlayback() }
    }
}
