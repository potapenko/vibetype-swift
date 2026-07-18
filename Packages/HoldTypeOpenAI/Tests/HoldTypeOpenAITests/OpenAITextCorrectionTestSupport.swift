import Foundation
import Testing
@testable import HoldTypeOpenAI

func expectCorrectionError(
    _ expectedError: OpenAITextCorrectionServiceError,
    operation: () async throws -> String
) async {
    do {
        _ = try await operation()
        Issue.record("Expected OpenAITextCorrectionServiceError.\(expectedError)")
    } catch let error as OpenAITextCorrectionServiceError {
        #expect(error == expectedError)
    } catch {
        Issue.record("Expected OpenAITextCorrectionServiceError, got \(error)")
    }
}

func makeCorrectionHTTPResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: OpenAITextCorrectionService.defaultEndpointURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

final class CorrectionFakeURLLoader: URLLoading, @unchecked Sendable {
    enum Result {
        case success(Data, URLResponse)
        case delayedSuccess(Data, URLResponse)
        case failure(Error)
    }

    private let result: Result
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []
    private var storedCancellationCount = 0

    var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    var cancellationCount: Int {
        lock.withLock { storedCancellationCount }
    }

    init(result: Result) {
        self.result = result
    }

    func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock {
            storedRequests.append(request)
        }

        switch result {
        case let .success(data, response):
            return (data, response)
        case let .delayedSuccess(data, response):
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                return (data, response)
            } catch is CancellationError {
                lock.withLock {
                    storedCancellationCount += 1
                }
                throw CancellationError()
            }
        case let .failure(error):
            throw error
        }
    }

    func waitForCancellationCount(_ expectedCount: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while cancellationCount < expectedCount, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }

        guard cancellationCount >= expectedCount else {
            throw CorrectionTestWaitError.timedOutWaitingForCancellationCount(
                expectedCount
            )
        }
    }
}

actor CorrectionSequencedURLLoader: URLLoading {
    enum Step {
        case success(Data, URLResponse)
        case waitForCancellation
        case lateSuccessAfterCancellation(Data, URLResponse)
    }

    private let steps: [Step]
    private var requestCount = 0
    private var cancellationCount = 0

    init(steps: [Step]) {
        self.steps = steps
    }

    func loadData(for _: URLRequest) async throws -> (Data, URLResponse) {
        let index = requestCount
        requestCount += 1

        guard steps.indices.contains(index) else {
            throw URLError(.badServerResponse)
        }

        switch steps[index] {
        case let .success(data, response):
            return (data, response)
        case .waitForCancellation:
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                throw URLError(.timedOut)
            } catch is CancellationError {
                cancellationCount += 1
                throw CancellationError()
            }
        case let .lateSuccessAfterCancellation(data, response):
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch is CancellationError {
                cancellationCount += 1
            }
            return (data, response)
        }
    }

    func waitForRequestCount(_ expectedCount: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while requestCount < expectedCount, clock.now < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        guard requestCount >= expectedCount else {
            throw CorrectionTestWaitError.timedOutWaitingForRequestCount(expectedCount)
        }
    }

    func observedCancellationCount() -> Int {
        cancellationCount
    }

    func waitForCancellationCount(_ expectedCount: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while cancellationCount < expectedCount, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }

        guard cancellationCount >= expectedCount else {
            throw CorrectionTestWaitError.timedOutWaitingForCancellationCount(
                expectedCount
            )
        }
    }
}

enum CorrectionTestWaitError: Error {
    case timedOutWaitingForRequestCount(Int)
    case timedOutWaitingForCancellationCount(Int)
}

final class CorrectionFakeTimeoutSleeper: TranscriptionTimeoutSleeping, @unchecked Sendable {
    enum Mode {
        case waitForCancellation
        case timeoutImmediately
    }

    private let mode: Mode
    private let lock = NSLock()
    private var storedSleepCalls: [TimeInterval] = []

    var sleepCalls: [TimeInterval] {
        lock.withLock { storedSleepCalls }
    }

    init(mode: Mode = .waitForCancellation) {
        self.mode = mode
    }

    func sleep(seconds: TimeInterval) async throws {
        lock.withLock {
            storedSleepCalls.append(seconds)
        }

        switch mode {
        case .waitForCancellation:
            try await Task.sleep(nanoseconds: 1_000_000_000)
        case .timeoutImmediately:
            return
        }
    }
}
