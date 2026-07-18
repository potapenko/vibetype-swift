@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct OpenAIProviderServicesIOSTests {
    @Test func containingAppInitializationSchedulesProviderAndLocalRecovery()
        async throws {
        var scheduleCount = 0
        let recoveryRecorder = ContainingAppRecoveryInvocationRecorder()

        _ = HoldTypeIOSApp(
            scheduleProviderStartupMaintenance: {
                scheduleCount += 1
            },
            recoverContainingAppLifecycle: { opportunity in
                await recoveryRecorder.record(opportunity)
                return .complete
            }
        )

        #expect(scheduleCount == 1)
        try await containingAppEventually {
            await recoveryRecorder.opportunities() == [.processLaunch]
        }
    }
}

private actor ContainingAppRecoveryInvocationRecorder {
    private var values: [IOSV1ContainingAppRecoveryOpportunity] = []

    func record(_ opportunity: IOSV1ContainingAppRecoveryOpportunity) {
        values.append(opportunity)
    }

    func opportunities() -> [IOSV1ContainingAppRecoveryOpportunity] {
        values
    }
}

private func containingAppEventually(
    _ predicate: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0..<100 {
        if await predicate() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for containing-app startup recovery.")
}
