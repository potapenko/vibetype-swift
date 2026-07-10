//
//  OpenAITextTranslationServiceTests.swift
//  HoldTypeTests
//
//  Created by Codex on 7/5/26.
//

import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeOpenAI

struct OpenAITextTranslationServiceTests {

    @Test func successfulOutputTextReturnsTranslationAndAuthorizedRequest() async throws {
        let loader = TranslationFakeURLLoader(
            result: .success(
                Data(#"{"output_text":"  Hello, world. \n"}"#.utf8),
                makeTranslationHTTPResponse(statusCode: 200)
            )
        )
        let sleeper = TranslationFakeTimeoutSleeper()
        let service = makeService(
            loader: loader,
            sleeper: sleeper,
            requestTimeout: 4
        )
        let translationRequest = TextTranslationRequest(
            acceptedTranscript: try AcceptedTranscript(rawText: "  Hola, mundo. \n"),
            translationConfiguration: TranslationConfiguration(
                targetLanguage: .english,
                model: "gpt-translation-test",
                prompt: "Prefer concise product UI wording."
            ),
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "unrelated-transcription-model",
                language: .spanish,
                freeformPrompt: "private transcription instructions"
            )
        )

        let translation = try await service.translate(
            translationRequest,
            credential: testCredential("sk-test-secret")
        )

        #expect(translation == "Hello, world.")
        #expect(loader.requests.count == 1)

        let request = try #require(loader.requests.first)
        #expect(request.url == OpenAITextTranslationService.defaultEndpointURL)
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 4)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-secret")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.httpBody?.contains(Data("sk-test-secret".utf8)) == false)
        #expect(sleeper.sleepCalls == [4])

        let payload = try decodedRequestPayload(from: request)
        #expect(payload["model"] as? String == "gpt-translation-test")
        #expect(payload["tool_choice"] as? String == "none")
        #expect(payload["store"] as? Bool == false)
        #expect(payload["max_output_tokens"] as? Int == OpenAITextTranslationService.defaultMaxOutputTokens)
        let instructions = try #require(payload["instructions"] as? String)
        #expect(instructions.contains("language code es"))
        #expect(instructions.contains("language code en"))
        #expect(instructions.contains("Prefer concise product UI wording."))
        #expect(instructions.contains("private transcription instructions") == false)
        #expect(instructions.contains("unrelated-transcription-model") == false)
        #expect(instructions.contains("Russian") == false)

        let reasoning = try #require(payload["reasoning"] as? [String: Any])
        #expect(reasoning["effort"] as? String == "low")

        let text = try #require(payload["text"] as? [String: Any])
        #expect(text["verbosity"] as? String == "low")

        let input = try #require(payload["input"] as? [[String: Any]])
        let firstMessage = try #require(input.first)
        let content = try #require(firstMessage["content"] as? [[String: Any]])
        let firstContent = try #require(content.first)
        #expect(firstContent["type"] as? String == "input_text")
        #expect(firstContent["text"] as? String == "Hola, mundo.")
    }

    @Test func autoTranscriptionSourceOmitsSourceLanguageInstruction() async throws {
        let loader = TranslationFakeURLLoader(
            result: .success(
                Data(#"{"output_text":"Hello."}"#.utf8),
                makeTranslationHTTPResponse(statusCode: 200)
            )
        )
        let service = makeService(loader: loader)
        _ = try await service.translate(
            try configuredTranslationRequest(
                "Hola.",
                transcriptionConfiguration: TranscriptionConfiguration(language: .automatic)
            ),
            credential: testCredential()
        )

        let request = try #require(loader.requests.first)
        let payload = try decodedRequestPayload(from: request)
        let instructions = try #require(payload["instructions"] as? String)
        #expect(instructions.contains("Translate the user's transcript to language code en."))
        #expect(instructions.contains("from language code") == false)
    }

    @Test func outputArrayFallbackReturnsTranslationText() async throws {
        let service = makeService(
            loader: TranslationFakeURLLoader(
                result: .success(
                    Data(
                        #"""
                        {
                          "output": [
                            {
                              "type": "message",
                              "content": [
                                {"type": "output_text", "text": "Translated from array"}
                              ]
                            }
                          ]
                        }
                        """#.utf8
                    ),
                    makeTranslationHTTPResponse(statusCode: 200)
                )
            )
        )

        let translation = try await service.translate(
            try configuredTranslationRequest("сырой текст"),
            credential: testCredential()
        )

        #expect(translation == "Translated from array")
    }

    @Test func timeoutMapsToTranslationTimeout() async throws {
        let loader = TranslationFakeURLLoader(
            result: .delayedSuccess(
                Data(#"{"output_text":"late"}"#.utf8),
                makeTranslationHTTPResponse(statusCode: 200)
            )
        )
        let sleeper = TranslationFakeTimeoutSleeper(mode: .timeoutImmediately)
        let service = makeService(loader: loader, sleeper: sleeper, requestTimeout: 2)

        await expectTranslationError(.timedOut) {
            try await service.translate(
                try configuredTranslationRequest("transcript"),
                credential: testCredential()
            )
        }

        #expect(loader.requests.count == 1)
        try await loader.waitForCancellationCount(1)
        #expect(loader.cancellationCount == 1)
        #expect(sleeper.sleepCalls == [2])
    }

    @Test func cancellationStopsTransportAndNextRequestSucceedsIndependently() async throws {
        let loader = TranslationSequencedURLLoader(
            steps: [
                .waitForCancellation,
                .success(
                    Data(#"{"output_text":"fresh translation"}"#.utf8),
                    makeTranslationHTTPResponse(statusCode: 200)
                ),
            ]
        )
        let service = makeService(loader: loader)
        let request = try configuredTranslationRequest("transcript")
        let credential = try testCredential()

        service.cancelActiveTranslation()
        let cancelledTask = Task {
            try await service.translate(
                request,
                credential: credential
            )
        }
        try await loader.waitForRequestCount(1)

        service.cancelActiveTranslation()
        service.cancelActiveTranslation()

        await expectTranslationError(.cancelled) {
            try await cancelledTask.value
        }
        try await loader.waitForCancellationCount(1)
        #expect(await loader.observedCancellationCount() == 1)

        let translation = try await service.translate(
            request,
            credential: credential
        )
        #expect(translation == "fresh translation")

        service.cancelActiveTranslation()
    }

    @Test func cancellationCompletesBeforeNonCooperativeLoaderReturns() async throws {
        let loader = ControlledURLLoader(cancellationBehaviors: [.awaitResponse])
        let service = makeService(loader: loader)
        let request = try configuredTranslationRequest("transcript")
        let credential = try testCredential()
        let resultProbe = AsyncOperationResultProbe<String>()
        let lateResponse = makeTranslationHTTPResponse(statusCode: 200)
        defer {
            loader.resolveRequest(
                at: 0,
                data: Data(#"{"output_text":"late translation"}"#.utf8),
                response: lateResponse
            )
        }

        let translation = Task {
            do {
                let result = try await service.translate(
                    request,
                    credential: credential
                )
                resultProbe.complete(with: .success(result))
            } catch {
                resultProbe.complete(with: .failure(error))
            }
        }
        try await loader.waitForRequestCount(1)

        service.cancelActiveTranslation()

        try await loader.waitForCancellation(ofRequestAt: 0)
        let result = try await resultProbe.waitForResult()
        switch result {
        case .success:
            Issue.record("Expected cancellation before the loader returned.")
        case let .failure(error as OpenAITextTranslationServiceError):
            #expect(error == .cancelled)
        case let .failure(error):
            Issue.record("Expected OpenAITextTranslationServiceError.cancelled, got \(error)")
        }
        await translation.value
    }

    @Test func lateCancelledResponseCannotPublishOrClearNewActiveRequest() async throws {
        let loader = TranslationSequencedURLLoader(
            steps: [
                .lateSuccessAfterCancellation(
                    Data(#"{"output_text":"late translation"}"#.utf8),
                    makeTranslationHTTPResponse(statusCode: 200)
                ),
                .waitForCancellation,
            ]
        )
        let service = makeService(loader: loader)
        let request = try configuredTranslationRequest("transcript")
        let credential = try testCredential()

        let oldTask = Task {
            try await service.translate(
                request,
                credential: credential
            )
        }
        try await loader.waitForRequestCount(1)

        let newTask = Task {
            try await service.translate(
                request,
                credential: credential
            )
        }
        try await loader.waitForRequestCount(2)

        await expectTranslationError(.cancelled) {
            try await oldTask.value
        }

        service.cancelActiveTranslation()

        await expectTranslationError(.cancelled) {
            try await newTask.value
        }
        try await loader.waitForCancellationCount(2)
        #expect(await loader.observedCancellationCount() == 2)
    }

    @Test func invalidProviderResponseIsRejected() async throws {
        let service = makeService(
            loader: TranslationFakeURLLoader(
                result: .success(
                    Data(#"{"output":[{"type":"message","content":[]}]}"#.utf8),
                    makeTranslationHTTPResponse(statusCode: 200)
                )
            )
        )

        await expectTranslationError(.emptyTranslation) {
            try await service.translate(
                try configuredTranslationRequest("transcript"),
                credential: testCredential()
            )
        }
    }

    @Test func providerStatusCodesMapToProductErrors() async throws {
        let cases: [(Int, OpenAITextTranslationServiceError)] = [
            (401, .invalidAPIKey),
            (429, .rateLimited),
            (500, .providerUnavailable),
            (418, .providerRejected(statusCode: 418)),
        ]

        for (statusCode, expectedError) in cases {
            let service = makeService(
                loader: TranslationFakeURLLoader(
                    result: .success(
                        Data(#"{"error":"unused"}"#.utf8),
                        makeTranslationHTTPResponse(statusCode: statusCode)
                    )
                )
            )

            await expectTranslationError(expectedError) {
                try await service.translate(
                    try configuredTranslationRequest("transcript"),
                    credential: testCredential()
                )
            }
        }
    }

    @Test func invalidLanguageConfigurationStopsBeforeNetworkRequest() async throws {
        let loader = TranslationFakeURLLoader(
            result: .success(Data(#"{"output_text":"unused"}"#.utf8), makeTranslationHTTPResponse(statusCode: 200))
        )
        let service = makeService(loader: loader)
        let request = TextTranslationRequest(
            acceptedTranscript: try AcceptedTranscript(rawText: "transcript"),
            translationConfiguration: TranslationConfiguration(
                sourceMode: .override,
                sourceLanguage: .custom,
                customSourceLanguageCode: "",
                targetLanguage: .english
            ),
            transcriptionConfiguration: .defaults
        )

        await expectTranslationError(.invalidLanguageConfiguration) {
            try await service.translate(
                request,
                credential: testCredential()
            )
        }

        #expect(loader.requests.isEmpty)
    }

    @Test func missingTargetLanguageStopsBeforeNetworkRequest() async throws {
        let loader = TranslationFakeURLLoader(
            result: .success(Data(#"{"output_text":"unused"}"#.utf8), makeTranslationHTTPResponse(statusCode: 200))
        )
        let service = makeService(loader: loader)

        let request = TextTranslationRequest(
            acceptedTranscript: try AcceptedTranscript(rawText: "transcript"),
            translationConfiguration: .defaults,
            transcriptionConfiguration: .defaults
        )

        await expectTranslationError(.invalidLanguageConfiguration) {
            try await service.translate(
                request,
                credential: testCredential()
            )
        }

        #expect(loader.requests.isEmpty)
    }

    private func makeService(
        loader: any URLLoading,
        sleeper: TranslationFakeTimeoutSleeper = TranslationFakeTimeoutSleeper(),
        requestTimeout: TimeInterval = 5
    ) -> OpenAITextTranslationService {
        OpenAITextTranslationService(
            endpointURL: OpenAITextTranslationService.defaultEndpointURL,
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

private func configuredTranslationRequest(
    _ transcript: String,
    transcriptionConfiguration: TranscriptionConfiguration = .defaults
) throws -> TextTranslationRequest {
    TextTranslationRequest(
        acceptedTranscript: try AcceptedTranscript(rawText: transcript),
        translationConfiguration: TranslationConfiguration(targetLanguage: .english),
        transcriptionConfiguration: transcriptionConfiguration
    )
}

private func expectTranslationError(
    _ expectedError: OpenAITextTranslationServiceError,
    operation: () async throws -> String
) async {
    do {
        _ = try await operation()
        Issue.record("Expected OpenAITextTranslationServiceError.\(expectedError)")
    } catch let error as OpenAITextTranslationServiceError {
        #expect(error == expectedError)
    } catch {
        Issue.record("Expected OpenAITextTranslationServiceError, got \(error)")
    }
}

private func makeTranslationHTTPResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: OpenAITextTranslationService.defaultEndpointURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private final class TranslationFakeURLLoader: URLLoading, @unchecked Sendable {
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
            throw TranslationTestWaitError.timedOutWaitingForCancellationCount(
                expectedCount
            )
        }
    }
}

private actor TranslationSequencedURLLoader: URLLoading {
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
            throw TranslationTestWaitError.timedOutWaitingForRequestCount(expectedCount)
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
            throw TranslationTestWaitError.timedOutWaitingForCancellationCount(
                expectedCount
            )
        }
    }
}

private enum TranslationTestWaitError: Error {
    case timedOutWaitingForRequestCount(Int)
    case timedOutWaitingForCancellationCount(Int)
}

private final class TranslationFakeTimeoutSleeper: TranscriptionTimeoutSleeping, @unchecked Sendable {
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
