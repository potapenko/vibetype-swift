//
//  OpenAITextCorrectionServiceTests.swift
//  HoldTypeTests
//
//  Created by Codex on 7/5/26.
//

import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeOpenAI

struct OpenAITextCorrectionServiceTests {

    @Test func successfulOutputTextReturnsCorrectionAndAuthorizedRequest() async throws {
        let loader = CorrectionFakeURLLoader(
            result: .success(
                Data(#"{"output_text":"  Corrected text. \n"}"#.utf8),
                makeCorrectionHTTPResponse(statusCode: 200)
            )
        )
        let sleeper = CorrectionFakeTimeoutSleeper()
        let service = makeService(
            loader: loader,
            sleeper: sleeper,
            requestTimeout: 4
        )
        let configuration = TextCorrectionConfiguration(
            isEnabled: true,
            modelPreset: .custom,
            customModel: "gpt-correction-test",
            prompt: "Fix only obvious errors."
        )

        let correction = try await service.correct(
            try AcceptedTranscript(rawText: "  hello text \n"),
            configuration: configuration,
            credential: testCredential("sk-test-secret")
        )

        #expect(correction == "Corrected text.")
        #expect(loader.requests.count == 1)

        let request = try #require(loader.requests.first)
        #expect(request.url == OpenAITextCorrectionService.defaultEndpointURL)
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 4)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-secret")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody?.contains(Data("sk-test-secret".utf8)) == false)
        #expect(sleeper.sleepCalls == [4])

        let payload = try decodedRequestPayload(from: request)
        #expect(payload["model"] as? String == "gpt-correction-test")
        #expect(payload["instructions"] as? String == "Fix only obvious errors.")
        #expect(payload["tool_choice"] as? String == "none")
        #expect(payload["store"] as? Bool == false)
        #expect(payload["max_output_tokens"] as? Int == OpenAITextCorrectionService.defaultMaxOutputTokens)

        let reasoning = try #require(payload["reasoning"] as? [String: Any])
        #expect(reasoning["effort"] as? String == "low")

        let text = try #require(payload["text"] as? [String: Any])
        #expect(text["verbosity"] as? String == "low")

        let input = try #require(payload["input"] as? [[String: Any]])
        let firstMessage = try #require(input.first)
        let content = try #require(firstMessage["content"] as? [[String: Any]])
        let firstContent = try #require(content.first)
        #expect(firstContent["type"] as? String == "input_text")
        #expect(firstContent["text"] as? String == "hello text")
    }

    @Test func outputArrayFallbackReturnsCorrectionText() async throws {
        let service = makeService(
            loader: CorrectionFakeURLLoader(
                result: .success(
                    Data(
                        #"""
                        {
                          "output": [
                            {
                              "type": "message",
                              "content": [
                                {"type": "output_text", "text": "Corrected from array"}
                              ]
                            }
                          ]
                        }
                        """#.utf8
                    ),
                    makeCorrectionHTTPResponse(statusCode: 200)
                )
            )
        )

        let correction = try await service.correct(
            try AcceptedTranscript(rawText: "raw text"),
            configuration: .defaults,
            credential: testCredential()
        )

        #expect(correction == "Corrected from array")
    }

    @Test func timeoutMapsToTextCorrectionTimeout() async throws {
        let loader = CorrectionFakeURLLoader(
            result: .delayedSuccess(
                Data(#"{"output_text":"late"}"#.utf8),
                makeCorrectionHTTPResponse(statusCode: 200)
            )
        )
        let sleeper = CorrectionFakeTimeoutSleeper(mode: .timeoutImmediately)
        let service = makeService(loader: loader, sleeper: sleeper, requestTimeout: 2)
        let transcript = try AcceptedTranscript(rawText: "transcript")

        await expectCorrectionError(.timedOut) {
            try await service.correct(
                transcript,
                configuration: .defaults,
                credential: testCredential()
            )
        }

        #expect(loader.requests.count == 1)
        try await loader.waitForCancellationCount(1)
        #expect(loader.cancellationCount == 1)
        #expect(sleeper.sleepCalls == [2])
    }

    @Test func cancellationStopsTransportAndNextRequestSucceedsIndependently() async throws {
        let loader = CorrectionSequencedURLLoader(
            steps: [
                .waitForCancellation,
                .success(
                    Data(#"{"output_text":"fresh correction"}"#.utf8),
                    makeCorrectionHTTPResponse(statusCode: 200)
                ),
            ]
        )
        let service = makeService(loader: loader)
        let transcript = try AcceptedTranscript(rawText: "transcript")
        let credential = try testCredential()

        service.cancelActiveCorrection()
        let cancelledTask = Task {
            try await service.correct(
                transcript,
                configuration: .defaults,
                credential: credential
            )
        }
        try await loader.waitForRequestCount(1)

        service.cancelActiveCorrection()
        service.cancelActiveCorrection()

        await expectCorrectionError(.cancelled) {
            try await cancelledTask.value
        }
        try await loader.waitForCancellationCount(1)
        #expect(await loader.observedCancellationCount() == 1)

        let correction = try await service.correct(
            transcript,
            configuration: .defaults,
            credential: credential
        )
        #expect(correction == "fresh correction")

        service.cancelActiveCorrection()
    }

    @Test func cancellationCompletesBeforeNonCooperativeLoaderReturns() async throws {
        let loader = ControlledURLLoader(cancellationBehaviors: [.awaitResponse])
        let service = makeService(loader: loader)
        let transcript = try AcceptedTranscript(rawText: "transcript")
        let credential = try testCredential()
        let resultProbe = AsyncOperationResultProbe<String>()
        let lateResponse = makeCorrectionHTTPResponse(statusCode: 200)
        defer {
            loader.resolveRequest(
                at: 0,
                data: Data(#"{"output_text":"late correction"}"#.utf8),
                response: lateResponse
            )
        }

        let correction = Task {
            do {
                let result = try await service.correct(
                    transcript,
                    configuration: .defaults,
                    credential: credential
                )
                resultProbe.complete(with: .success(result))
            } catch {
                resultProbe.complete(with: .failure(error))
            }
        }
        try await loader.waitForRequestCount(1)

        service.cancelActiveCorrection()

        try await loader.waitForCancellation(ofRequestAt: 0)
        let result = try await resultProbe.waitForResult()
        switch result {
        case .success:
            Issue.record("Expected cancellation before the loader returned.")
        case let .failure(error as OpenAITextCorrectionServiceError):
            #expect(error == .cancelled)
        case let .failure(error):
            Issue.record("Expected OpenAITextCorrectionServiceError.cancelled, got \(error)")
        }
        await correction.value
    }

    @Test func lateCancelledResponseCannotPublishOrClearNewActiveRequest() async throws {
        let loader = CorrectionSequencedURLLoader(
            steps: [
                .lateSuccessAfterCancellation(
                    Data(#"{"output_text":"late correction"}"#.utf8),
                    makeCorrectionHTTPResponse(statusCode: 200)
                ),
                .waitForCancellation,
            ]
        )
        let service = makeService(loader: loader)
        let transcript = try AcceptedTranscript(rawText: "transcript")
        let credential = try testCredential()

        let oldTask = Task {
            try await service.correct(
                transcript,
                configuration: .defaults,
                credential: credential
            )
        }
        try await loader.waitForRequestCount(1)

        let newTask = Task {
            try await service.correct(
                transcript,
                configuration: .defaults,
                credential: credential
            )
        }
        try await loader.waitForRequestCount(2)

        await expectCorrectionError(.cancelled) {
            try await oldTask.value
        }

        service.cancelActiveCorrection()

        await expectCorrectionError(.cancelled) {
            try await newTask.value
        }
        try await loader.waitForCancellationCount(2)
        #expect(await loader.observedCancellationCount() == 2)
    }

    @Test func invalidProviderResponseIsRejected() async throws {
        let service = makeService(
            loader: CorrectionFakeURLLoader(
                result: .success(
                    Data(#"{"output":[{"type":"message","content":[]}]}"#.utf8),
                    makeCorrectionHTTPResponse(statusCode: 200)
                )
            )
        )
        let transcript = try AcceptedTranscript(rawText: "transcript")

        await expectCorrectionError(.emptyCorrection) {
            try await service.correct(
                transcript,
                configuration: .defaults,
                credential: testCredential()
            )
        }
    }

    @Test func providerStatusCodesMapToProductErrors() async throws {
        let cases: [(Int, OpenAITextCorrectionServiceError)] = [
            (401, .invalidAPIKey),
            (429, .rateLimited),
            (500, .providerUnavailable),
            (418, .providerRejected(statusCode: 418)),
        ]
        let transcript = try AcceptedTranscript(rawText: "transcript")

        for (statusCode, expectedError) in cases {
            let service = makeService(
                loader: CorrectionFakeURLLoader(
                    result: .success(Data(#"{"error":"unused"}"#.utf8), makeCorrectionHTTPResponse(statusCode: statusCode))
                )
            )

            await expectCorrectionError(expectedError) {
                try await service.correct(
                    transcript,
                    configuration: .defaults,
                    credential: testCredential()
                )
            }
        }
    }

    private func makeService(
        loader: any URLLoading,
        sleeper: CorrectionFakeTimeoutSleeper = CorrectionFakeTimeoutSleeper(),
        requestTimeout: TimeInterval = 5
    ) -> OpenAITextCorrectionService {
        OpenAITextCorrectionService(
            endpointURL: OpenAITextCorrectionService.defaultEndpointURL,
            urlLoader: loader,
            timeoutSleeper: sleeper,
            requestTimeout: requestTimeout
        )
    }

    private func testCredential(_ apiKey: String = "sk-test") throws -> OpenAICredential {
        try OpenAICredential(apiKey: apiKey)
    }

    private func decodedRequestPayload(from request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}

private func expectCorrectionError(
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

private func makeCorrectionHTTPResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: OpenAITextCorrectionService.defaultEndpointURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private final class CorrectionFakeURLLoader: URLLoading, @unchecked Sendable {
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

private actor CorrectionSequencedURLLoader: URLLoading {
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

private enum CorrectionTestWaitError: Error {
    case timedOutWaitingForRequestCount(Int)
    case timedOutWaitingForCancellationCount(Int)
}

private final class CorrectionFakeTimeoutSleeper: TranscriptionTimeoutSleeping, @unchecked Sendable {
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
