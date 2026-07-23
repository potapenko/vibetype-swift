import Testing
import UIKit
@testable import HoldTypeIOS

@MainActor
struct IOSKeyboardFixBackgroundTaskAdapterTests {
    @Test func endIsIdempotentForOneRegisteredBackgroundTask() async {
        let identifier = UIBackgroundTaskIdentifier(rawValue: 42)
        var ended: [UIBackgroundTaskIdentifier] = []
        let registry = IOSKeyboardFixBackgroundTaskRegistry(
            beginSystemTask: { _ in identifier },
            endSystemTask: { ended.append($0) }
        )

        let token = await registry.client.begin {}
        await registry.client.end(token)
        await registry.client.end(token)

        #expect(ended == [identifier])
    }

    @Test func expirationCancelsAndEndsBeforeLateProcessorCleanup() async {
        let identifier = UIBackgroundTaskIdentifier(rawValue: 9)
        var expirationHandler: (() -> Void)?
        let cancellations = IOSKeyboardFixCancellationProbe()
        var ended: [UIBackgroundTaskIdentifier] = []
        let registry = IOSKeyboardFixBackgroundTaskRegistry(
            beginSystemTask: {
                expirationHandler = $0
                return identifier
            },
            endSystemTask: { ended.append($0) }
        )

        let token = await registry.client.begin {
            cancellations.record()
        }
        expirationHandler?()
        await Task.yield()
        await registry.client.end(token)

        #expect(cancellations.count == 1)
        #expect(ended == [identifier])
    }
}

private final class IOSKeyboardFixCancellationProbe:
    @unchecked Sendable {
    private let lock = NSLock()
    private var countStorage = 0

    var count: Int {
        lock.withLock { countStorage }
    }

    func record() {
        lock.withLock {
            countStorage += 1
        }
    }
}
