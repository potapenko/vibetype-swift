import Foundation
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSMicrophonePermissionAdapterTests {
    @Test func passiveReadsNeverRequestPermission() async {
        for status in [
            IOSMicrophonePermissionStatus.granted,
            .denied,
            .unavailable,
        ] {
            let state = MicrophonePermissionFake(status: status)
            let adapter = IOSMicrophonePermissionAdapter(
                client: state.client
            )

            #expect(adapter.currentStatus() == status)
            let requestedStatus = await adapter.requestIfUndetermined()
            #expect(requestedStatus == status)
            #expect(state.requestCount == 0)
        }
    }

    @Test func explicitUndeterminedRequestRereadsAuthoritativeStatus()
        async throws {
        let request = MicrophonePermissionRequestLatch()
        let state = MicrophonePermissionFake(
            status: .undetermined,
            request: {
                await request.wait()
            }
        )
        let adapter = IOSMicrophonePermissionAdapter(client: state.client)

        async let first = adapter.requestIfUndetermined()
        async let second = adapter.requestIfUndetermined()
        try await permissionEventually { state.requestCount == 1 }
        #expect(adapter.currentStatus() == .undetermined)

        state.status = .granted
        await request.open()
        let firstStatus = await first
        let secondStatus = await second
        #expect(firstStatus == .granted)
        #expect(secondStatus == .granted)
        #expect(state.requestCount == 1)
    }

    @Test func callbackValueCannotOverrideThePostRequestTruth() async {
        let state = MicrophonePermissionFake(
            status: .undetermined,
            request: {}
        )
        let adapter = IOSMicrophonePermissionAdapter(client: state.client)

        let status = await adapter.requestIfUndetermined()
        #expect(status == .undetermined)
        #expect(state.requestCount == 1)
    }

    @Test func diagnosticsAndReflectionAreRedacted() {
        let state = MicrophonePermissionFake(status: .denied)
        let adapter = IOSMicrophonePermissionAdapter(client: state.client)
        let canary = "microphone-permission-canary"

        for value in [
            String(describing: IOSMicrophonePermissionStatus.denied),
            String(reflecting: IOSMicrophonePermissionStatus.denied),
            String(describing: state.client),
            String(reflecting: state.client),
            String(describing: adapter),
            String(reflecting: adapter),
        ] {
            #expect(!value.contains(canary))
            #expect(value.contains("<redacted>"))
        }
        #expect(Mirror(reflecting: state.client).children.isEmpty)
        #expect(Mirror(reflecting: adapter).children.isEmpty)
    }
}

@MainActor
private final class MicrophonePermissionFake {
    var status: IOSMicrophonePermissionStatus
    private let requestAction: @MainActor @Sendable () async -> Void
    private(set) var requestCount = 0

    init(
        status: IOSMicrophonePermissionStatus,
        request: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        self.status = status
        requestAction = request
    }

    var client: IOSMicrophonePermissionClient {
        IOSMicrophonePermissionClient(
            read: { [weak self] in self?.status ?? .unavailable },
            request: { [weak self] in
                guard let self else { return }
                requestCount += 1
                await requestAction()
            }
        )
    }
}

private actor MicrophonePermissionRequestLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

@MainActor
private func permissionEventually(
    _ predicate: @escaping @MainActor @Sendable () -> Bool
) async throws {
    for _ in 0..<100 {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for permission adapter state.")
}
