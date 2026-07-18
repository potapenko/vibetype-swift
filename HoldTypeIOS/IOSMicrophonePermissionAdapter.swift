import AVFAudio

nonisolated enum IOSMicrophonePermissionStatus: Equatable, Sendable {
    case undetermined
    case denied
    case granted
    case unavailable
}

nonisolated enum IOSMicrophonePermissionRequestResult: Equatable, Sendable {
    case granted
    case denied
    case unavailable
    case timedOut
    case cancelled
}

nonisolated struct IOSMicrophonePermissionClient: Sendable {
    typealias Read = @MainActor @Sendable () ->
        IOSMicrophonePermissionStatus
    typealias Request = @MainActor @Sendable () async -> Void

    let read: Read
    let request: Request

    init(
        read: @escaping Read,
        request: @escaping Request
    ) {
        self.read = read
        self.request = request
    }

    nonisolated static let live = IOSMicrophonePermissionClient(
        read: {
            switch AVAudioApplication.shared.recordPermission {
            case .undetermined:
                .undetermined
            case .denied:
                .denied
            case .granted:
                .granted
            @unknown default:
                .unavailable
            }
        },
        request: {
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { _ in
                    continuation.resume()
                }
            }
        }
    )
}

@MainActor
final class IOSMicrophonePermissionAdapter {
    typealias Sleep = @MainActor @Sendable (Duration) async throws -> Void

    nonisolated static let requestTimeout = Duration.seconds(120)

    private final class RequestState {
        var waiters: [
            UInt64:
                CheckedContinuation<
                    IOSMicrophonePermissionRequestResult,
                    Never
                >
        ] = [:]
        var timeoutTask: Task<Void, Never>?
        var terminalResult: IOSMicrophonePermissionRequestResult?
        var acceptsWaiters = true

        func resolveWaitingCallers(
            with result: IOSMicrophonePermissionRequestResult
        ) {
            guard acceptsWaiters else { return }
            acceptsWaiters = false
            terminalResult = result
            timeoutTask?.cancel()
            timeoutTask = nil
            let waiters = waiters.values
            self.waiters.removeAll()
            for waiter in waiters {
                waiter.resume(returning: result)
            }
        }

        func abandonWaiter(_ identifier: UInt64) {
            guard let waiter = waiters.removeValue(
                forKey: identifier
            ) else {
                return
            }
            waiter.resume(returning: .cancelled)
            guard waiters.isEmpty else { return }
            acceptsWaiters = false
            timeoutTask?.cancel()
            timeoutTask = nil
        }
    }

    private let client: IOSMicrophonePermissionClient
    private let sleep: Sleep
    private let timeout: Duration
    private var activeRequest: RequestState?
    private var nextWaiterIdentifier: UInt64 = 0

    init(
        client: IOSMicrophonePermissionClient = .live,
        timeout: Duration = requestTimeout,
        sleep: @escaping Sleep = { duration in
            try await ContinuousClock().sleep(for: duration)
        }
    ) {
        self.client = client
        self.timeout = timeout
        self.sleep = sleep
    }

    func currentStatus() -> IOSMicrophonePermissionStatus {
        client.read()
    }

    func requestOutcomeIfUndetermined() async
        -> IOSMicrophonePermissionRequestResult {
        let observed = client.read()
        guard observed == .undetermined else {
            return Self.map(observed)
        }
        guard !Task.isCancelled else { return .cancelled }

        let request: RequestState
        if let activeRequest {
            guard activeRequest.acceptsWaiters else {
                return .unavailable
            }
            request = activeRequest
        } else {
            request = beginSystemRequest()
        }
        return await waitForRequest(request)
    }

    /// Transitional status projection for callers that have not yet adopted
    /// the typed bounded result. Production Voice composition uses
    /// `requestOutcomeIfUndetermined()` so timeout and cancellation remain
    /// distinguishable.
    func requestIfUndetermined() async -> IOSMicrophonePermissionStatus {
        let result = await requestOutcomeIfUndetermined()
        switch result {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .unavailable, .timedOut, .cancelled:
            let current = client.read()
            return current == .undetermined ? .unavailable : current
        }
    }

    private func beginSystemRequest() -> RequestState {
        let request = RequestState()
        activeRequest = request
        let client = client
        let timeout = timeout
        let sleep = sleep
        Task { @MainActor [weak self, request] in
            await client.request()
            let result = Self.map(client.read())
            request.resolveWaitingCallers(with: result)
            if self?.activeRequest === request {
                self?.activeRequest = nil
            }
        }
        request.timeoutTask = Task { @MainActor [request] in
            do {
                try await sleep(timeout)
            } catch {
                guard !Task.isCancelled else { return }
            }
            request.resolveWaitingCallers(with: .timedOut)
        }
        return request
    }

    private func waitForRequest(
        _ request: RequestState
    ) async -> IOSMicrophonePermissionRequestResult {
        nextWaiterIdentifier &+= 1
        if nextWaiterIdentifier == 0 { nextWaiterIdentifier = 1 }
        let waiterIdentifier = nextWaiterIdentifier
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let terminalResult = request.terminalResult {
                    continuation.resume(returning: terminalResult)
                } else if request.acceptsWaiters {
                    request.waiters[waiterIdentifier] = continuation
                    // Registration and the cancellation check happen in one
                    // MainActor turn. This closes the narrow race where the
                    // handler fires before a waiter exists and would otherwise
                    // leave an abandoned system prompt open to a later owner.
                    if Task.isCancelled {
                        request.abandonWaiter(waiterIdentifier)
                    }
                } else {
                    continuation.resume(returning: .unavailable)
                }
            }
        } onCancel: {
            Task { @MainActor [request] in
                request.abandonWaiter(waiterIdentifier)
            }
        }
    }

    private static func map(
        _ status: IOSMicrophonePermissionStatus
    ) -> IOSMicrophonePermissionRequestResult {
        switch status {
        case .granted:
            .granted
        case .denied:
            .denied
        case .undetermined, .unavailable:
            .unavailable
        }
    }
}

extension IOSMicrophonePermissionStatus:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSMicrophonePermissionStatus(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSMicrophonePermissionRequestResult:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSMicrophonePermissionRequestResult(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSMicrophonePermissionClient:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSMicrophonePermissionClient(<redacted>)"
    }

    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSMicrophonePermissionAdapter:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    nonisolated var description: String {
        "IOSMicrophonePermissionAdapter(<redacted>)"
    }

    nonisolated var debugDescription: String { description }
    nonisolated var customMirror: Mirror { Mirror(self, children: [:]) }
}
