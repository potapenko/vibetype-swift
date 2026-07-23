import Foundation
import Testing
@testable import HoldTypeIOS

struct IOSKeyboardFixProcessorCancellationTests {
    @Test func matchingCancellationWaitsRetiresLateResultAndAcknowledges()
        async throws {
        let request = try makeProcessorTestRequest()
        let cancellation = try makeAppCancellation(for: request)
        let bridge = IOSKeyboardFixCancellationBridgeProbe(
            request: request,
            cancellation: cancellation
        )
        let execution = IOSKeyboardFixTestExecutionGate()
        let signals = IOSKeyboardFixTestSignalProbe()
        let processor = makeKeyboardFixProcessor(
            bridge: bridge.client,
            now: request.issuedAt.addingTimeInterval(1),
            execute: execution.client.execute,
            signals: signals.client
        )
        let requestTask = Task {
            await processor.processPendingRequest()
        }
        try await processorEventually {
            execution.executeCount == 1
        }

        #expect(await processor.processPendingCancellation())
        let outcome = await requestTask.value

        #expect(outcome == .completed(.failed(.cancelled)))
        #expect(bridge.results.isEmpty)
        #expect(bridge.retiredRequestIDs == [request.requestID])
        #expect(bridge.acknowledgement?.phase == .acknowledged)
        #expect(
            signals.signals.contains(
                .cancellationAcknowledged(
                    requestID: request.requestID
                )
            )
        )
    }

    @Test func staleCancellationAWaitsForAckWithoutCancellingActiveB()
        async throws {
        let activeRequest = try makeProcessorTestRequest()
        let staleRequestID = UUID()
        let cancellation = try makeAppCancellation(
            requestID: staleRequestID,
            issuedAt: activeRequest.issuedAt
        )
        let bridge = IOSKeyboardFixCancellationBridgeProbe(
            request: activeRequest,
            cancellation: cancellation
        )
        let execution = IOSKeyboardFixTestExecutionGate(
            output: "B completed"
        )
        let processor = makeKeyboardFixProcessor(
            bridge: bridge.client,
            now: activeRequest.issuedAt.addingTimeInterval(1),
            execute: execution.client.execute
        )
        let requestTask = Task {
            await processor.processPendingRequest()
        }
        try await processorEventually {
            execution.executeCount == 1
        }

        #expect(await processor.processPendingCancellation())
        #expect(bridge.acknowledgement?.requestID == staleRequestID)
        #expect(bridge.retiredRequestIDs == [staleRequestID])
        execution.open()
        let outcome = await requestTask.value

        #expect(outcome == .completed(.succeeded))
        #expect(bridge.results.last?.requestID == activeRequest.requestID)
        #expect(bridge.results.last?.outputText == "B completed")
    }
}

private typealias AppKeyboardFixCancellation =
    HoldTypeIOS.KeyboardFixCancellationRecord

private func makeAppCancellation(
    for request: ProcessorTestRequest
) throws -> AppKeyboardFixCancellation {
    try makeAppCancellation(
        requestID: request.requestID,
        issuedAt: request.issuedAt
    )
}

private func makeAppCancellation(
    requestID: UUID,
    issuedAt: Date
) throws -> AppKeyboardFixCancellation {
    try #require(
        AppKeyboardFixCancellation(
            requestID: requestID,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(60)
        )
    )
}

private final class IOSKeyboardFixCancellationBridgeProbe:
    @unchecked Sendable {
    private let lock = NSLock()
    private var request: ProcessorTestRequest?
    private var cancellation: AppKeyboardFixCancellation?
    private var resultsStorage: [ProcessorTestResult] = []
    private var retiredRequestIDsStorage: [UUID] = []

    init(
        request: ProcessorTestRequest?,
        cancellation: AppKeyboardFixCancellation?
    ) {
        self.request = request
        self.cancellation = cancellation
    }

    var client: IOSKeyboardFixBridgeClient {
        IOSKeyboardFixBridgeClient(
            consumeRequest: { [self] _ in
                lock.withLock {
                    defer { request = nil }
                    return request
                }
            },
            consumeCancellation: { [self] _ in
                lock.withLock {
                    guard cancellation?.phase == .requested else {
                        return nil
                    }
                    return cancellation
                }
            },
            publishResult: { [self] result in
                lock.withLock {
                    resultsStorage.append(result)
                }
            },
            publishCancellationAcknowledgement: {
                [self] acknowledgement in
                lock.withLock {
                    guard cancellation?.phase == .requested,
                          cancellation?.requestID
                            == acknowledgement.requestID
                    else {
                        return false
                    }
                    cancellation = acknowledgement
                    return true
                }
            },
            retireRequest: { [self] requestID in
                lock.withLock {
                    retiredRequestIDsStorage.append(requestID)
                    if request?.requestID == requestID {
                        request = nil
                    }
                    resultsStorage.removeAll {
                        $0.requestID == requestID
                    }
                }
            }
        )
    }

    var results: [ProcessorTestResult] {
        lock.withLock { resultsStorage }
    }

    var acknowledgement: AppKeyboardFixCancellation? {
        lock.withLock {
            guard cancellation?.phase == .acknowledged else {
                return nil
            }
            return cancellation
        }
    }

    var retiredRequestIDs: [UUID] {
        lock.withLock { retiredRequestIDsStorage }
    }
}
