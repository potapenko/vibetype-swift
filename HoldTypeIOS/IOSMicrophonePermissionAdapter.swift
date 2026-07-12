import AVFAudio

nonisolated enum IOSMicrophonePermissionStatus: Equatable, Sendable {
    case undetermined
    case denied
    case granted
    case unavailable
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
    private let client: IOSMicrophonePermissionClient
    private var activeRequest:
        Task<IOSMicrophonePermissionStatus, Never>?

    init(client: IOSMicrophonePermissionClient = .live) {
        self.client = client
    }

    func currentStatus() -> IOSMicrophonePermissionStatus {
        client.read()
    }

    func requestIfUndetermined() async -> IOSMicrophonePermissionStatus {
        guard client.read() == .undetermined else {
            return client.read()
        }
        if let activeRequest {
            return await activeRequest.value
        }

        let client = client
        let task = Task { @MainActor in
            await client.request()
            return client.read()
        }
        activeRequest = task
        let status = await task.value
        activeRequest = nil
        return status
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
