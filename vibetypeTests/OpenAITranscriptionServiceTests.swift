//
//  OpenAITranscriptionServiceTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/21/26.
//

import Foundation
import Testing
@testable import vibetype

struct OpenAITranscriptionServiceTests {

    @Test func successfulResponseReturnsTrimmedTranscriptAndAuthorizedRequest() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = FakeURLLoader(
            result: .success(
                Data(#"{"text":"  Hello from VibeType \n"}"#.utf8),
                makeHTTPResponse(statusCode: 200)
            )
        )
        let sleeper = FakeTimeoutSleeper()
        let service = makeService(
            apiKey: "sk-test-secret",
            loader: loader,
            sleeper: sleeper,
            requestTimeout: 7
        )

        let transcript = try await service.transcribe(audioFileURL: audioFileURL, settings: .defaults)

        #expect(transcript == "Hello from VibeType")
        #expect(loader.requests.count == 1)

        let request = try #require(loader.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-secret")
        #expect(request.timeoutInterval == 7)
        #expect(request.httpBody?.contains(Data("sk-test-secret".utf8)) == false)
        #expect(sleeper.sleepCalls == [7])
    }

    @Test func missingAPIKeyStopsBeforeNetworkRequest() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = FakeURLLoader(
            result: .success(Data(#"{"text":"unused"}"#.utf8), makeHTTPResponse(statusCode: 200))
        )
        let service = makeService(apiKey: nil, loader: loader)

        await expectTranscriptionError(.missingAPIKey) {
            try await service.transcribe(audioFileURL: audioFileURL, settings: .defaults)
        }

        #expect(loader.requests.isEmpty)
    }

    @Test func keychainReadFailureStopsBeforeNetworkRequest() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = FakeURLLoader(
            result: .success(Data(#"{"text":"unused"}"#.utf8), makeHTTPResponse(statusCode: 200))
        )
        let service = OpenAITranscriptionService(
            apiKeyStorage: FakeAPIKeyStorage(loadError: KeychainServiceError.invalidStoredAPIKey),
            requestBuilder: OpenAITranscriptionRequestBuilder(boundary: "Boundary-Test"),
            urlLoader: loader,
            timeoutSleeper: FakeTimeoutSleeper(),
            requestTimeout: 7
        )

        await expectTranscriptionError(.apiKeyUnavailable) {
            try await service.transcribe(audioFileURL: audioFileURL, settings: .defaults)
        }

        #expect(loader.requests.isEmpty)
    }

    @Test func boundedTimeoutMapsToUserVisibleTimeoutError() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = FakeURLLoader(
            result: .delayedSuccess(
                Data(#"{"text":"late"}"#.utf8),
                makeHTTPResponse(statusCode: 200)
            )
        )
        let sleeper = FakeTimeoutSleeper(mode: .timeoutImmediately)
        let service = makeService(loader: loader, sleeper: sleeper, requestTimeout: 3)

        await expectTranscriptionError(.timedOut) {
            try await service.transcribe(audioFileURL: audioFileURL, settings: .defaults)
        }

        #expect(loader.requests.count == 1)
        #expect(loader.requests.first?.timeoutInterval == 3)
        #expect(sleeper.sleepCalls == [3])
    }

    @Test func urlSessionTimeoutErrorMapsToUserVisibleTimeoutError() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let service = makeService(loader: FakeURLLoader(result: .failure(URLError(.timedOut))))

        await expectTranscriptionError(.timedOut) {
            try await service.transcribe(audioFileURL: audioFileURL, settings: .defaults)
        }
    }

    @Test func urlLoadingFailuresMapToProductErrors() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let cases: [(URLError.Code, OpenAITranscriptionServiceError)] = [
            (.notConnectedToInternet, .networkUnavailable),
            (.networkConnectionLost, .networkUnavailable),
            (.cannotFindHost, .networkUnavailable),
            (.cannotConnectToHost, .networkUnavailable),
            (.cancelled, .cancelled),
            (.badServerResponse, .networkFailure),
        ]

        for (urlErrorCode, expectedError) in cases {
            let service = makeService(loader: FakeURLLoader(result: .failure(URLError(urlErrorCode))))

            await expectTranscriptionError(expectedError) {
                try await service.transcribe(audioFileURL: audioFileURL, settings: .defaults)
            }
        }
    }

    @Test func providerStatusCodesMapToProductErrors() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let cases: [(Int, OpenAITranscriptionServiceError)] = [
            (401, .invalidAPIKey),
            (403, .invalidAPIKey),
            (408, .timedOut),
            (429, .rateLimited),
            (400, .badRequest),
            (404, .badRequest),
            (413, .badRequest),
            (415, .badRequest),
            (422, .badRequest),
            (500, .providerUnavailable),
            (503, .providerUnavailable),
            (418, .providerRejected(statusCode: 418)),
        ]

        for (statusCode, expectedError) in cases {
            let service = makeService(
                loader: FakeURLLoader(
                    result: .success(Data(#"{"error":"not used"}"#.utf8), makeHTTPResponse(statusCode: statusCode))
                )
            )

            await expectTranscriptionError(expectedError) {
                try await service.transcribe(audioFileURL: audioFileURL, settings: .defaults)
            }
        }
    }

    @Test func emptyTranscriptIsRejected() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let service = makeService(
            loader: FakeURLLoader(
                result: .success(Data(#"{"text":"   \n"}"#.utf8), makeHTTPResponse(statusCode: 200))
            )
        )

        await expectTranscriptionError(.emptyTranscript) {
            try await service.transcribe(audioFileURL: audioFileURL, settings: .defaults)
        }
    }

    @Test func dictionaryEchoTranscriptIsRejected() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        var settings = AppSettings.defaults
        settings.customDictionary = ["OpenWhispr", "Parakeet", "Alcahest"]

        let service = makeService(
            loader: FakeURLLoader(
                result: .success(
                    Data(#"{"text":"OpenWhispr, Parakeet, Alcahest."}"#.utf8),
                    makeHTTPResponse(statusCode: 200)
                )
            )
        )

        await expectTranscriptionError(.dictionaryEcho) {
            try await service.transcribe(audioFileURL: audioFileURL, settings: settings)
        }
    }

    @Test func dictionaryEchoFilterDistinguishesEchoFromLegitimateSpeech() {
        #expect(
            DictionaryEchoFilter.matches(
                transcript: "OpenWhispr, Parakeet, Alcahest",
                dictionaryPrompt: "OpenWhispr, Parakeet, Alcahest"
            )
        )
        #expect(
            DictionaryEchoFilter.matches(
                transcript: "openwhispr parakeet alcahest",
                dictionaryPrompt: "OpenWhispr, Parakeet, Alcahest"
            )
        )
        #expect(
            DictionaryEchoFilter.matches(
                transcript: "I just installed OpenWhispr and it works great",
                dictionaryPrompt: "OpenWhispr, Parakeet, Alcahest"
            ) == false
        )
        #expect(DictionaryEchoFilter.matches(transcript: nil, dictionaryPrompt: "OpenWhispr") == false)
        #expect(DictionaryEchoFilter.matches(transcript: "OpenWhispr", dictionaryPrompt: nil) == false)
    }

    @Test func invalidResponseIsRejected() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let service = makeService(
            loader: FakeURLLoader(
                result: .success(Data(#"{"message":"missing text"}"#.utf8), makeHTTPResponse(statusCode: 200))
            )
        )

        await expectTranscriptionError(.invalidResponse) {
            try await service.transcribe(audioFileURL: audioFileURL, settings: .defaults)
        }
    }

    @Test func unsupportedRecordingErrorIsMappedBeforeNetworkRequest() async throws {
        let audioFileURL = try makeTemporaryAudioFile(named: "recording.txt")
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = FakeURLLoader(
            result: .success(Data(#"{"text":"unused"}"#.utf8), makeHTTPResponse(statusCode: 200))
        )
        let service = makeService(loader: loader)

        await expectTranscriptionError(.invalidRecording(.unsupportedAudioFileType("txt"))) {
            try await service.transcribe(audioFileURL: audioFileURL, settings: .defaults)
        }

        #expect(loader.requests.isEmpty)
    }

    @Test func emptyAudioFileErrorIsMappedBeforeNetworkRequest() async throws {
        let audioFileURL = try makeTemporaryAudioFile(contents: Data())
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = FakeURLLoader(
            result: .success(Data(#"{"text":"unused"}"#.utf8), makeHTTPResponse(statusCode: 200))
        )
        let service = makeService(loader: loader)

        await expectTranscriptionError(.invalidRecording(.emptyAudioFile(audioFileURL))) {
            try await service.transcribe(audioFileURL: audioFileURL, settings: .defaults)
        }

        #expect(loader.requests.isEmpty)
    }

    @Test func invalidCustomLanguageErrorIsMappedBeforeNetworkRequest() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        var settings = AppSettings.defaults
        settings.language = .custom
        settings.customLanguageCode = "en-US"

        let loader = FakeURLLoader(
            result: .success(Data(#"{"text":"unused"}"#.utf8), makeHTTPResponse(statusCode: 200))
        )
        let service = makeService(loader: loader)

        await expectTranscriptionError(.invalidRecording(.invalidCustomLanguageCode("en-US"))) {
            try await service.transcribe(audioFileURL: audioFileURL, settings: settings)
        }

        #expect(loader.requests.isEmpty)
    }

    @Test func commonFailureMessagesAndLogCategoriesAreStable() {
        let audioFileURL = URL(fileURLWithPath: "/tmp/recording.m4a")
        let cases: [(OpenAITranscriptionServiceError, String, String)] = [
            (
                .missingAPIKey,
                "Enter an OpenAI API key before transcribing.",
                "missing_api_key"
            ),
            (
                .invalidAPIKey,
                "OpenAI rejected the saved API key. Check Settings.",
                "invalid_api_key"
            ),
            (
                .rateLimited,
                "OpenAI rate limits were reached. Try again later.",
                "rate_limited"
            ),
            (
                .timedOut,
                "Transcription timed out.",
                "timeout"
            ),
            (
                .invalidRecording(.emptyAudioFile(audioFileURL)),
                "No audio was captured. Try recording again.",
                "empty_audio"
            ),
            (
                .invalidRecording(.invalidCustomLanguageCode("en-US")),
                "Use a two- or three-letter custom language code.",
                "invalid_language_code"
            ),
            (
                .providerUnavailable,
                "OpenAI is unavailable. Try again later.",
                "provider_unavailable"
            ),
            (
                .emptyTranscript,
                "No speech text was detected.",
                "empty_transcript"
            ),
            (
                .dictionaryEcho,
                "Only dictionary hints were detected.",
                "dictionary_echo"
            ),
        ]

        for (error, expectedMessage, expectedLogCategory) in cases {
            #expect(error.userFacingMessage == expectedMessage)
            #expect(error.errorDescription == expectedMessage)
            #expect(error.operatorLogCategory == expectedLogCategory)
        }
    }

    private func makeService(
        apiKey: String? = "sk-test",
        loader: FakeURLLoader,
        sleeper: FakeTimeoutSleeper = FakeTimeoutSleeper(),
        requestTimeout: TimeInterval = 7
    ) -> OpenAITranscriptionService {
        OpenAITranscriptionService(
            apiKeyStorage: FakeAPIKeyStorage(apiKey: apiKey),
            requestBuilder: OpenAITranscriptionRequestBuilder(boundary: "Boundary-Test"),
            urlLoader: loader,
            timeoutSleeper: sleeper,
            requestTimeout: requestTimeout
        )
    }

    private func makeTemporaryAudioFile(
        named fileName: String = "recording.m4a",
        contents: Data = Data("fake audio bytes".utf8)
    ) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibetype-transcription-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent(fileName)
        try contents.write(to: fileURL)
        return fileURL
    }
}

private func expectTranscriptionError(
    _ expectedError: OpenAITranscriptionServiceError,
    operation: () async throws -> String
) async {
    do {
        _ = try await operation()
        Issue.record("Expected OpenAITranscriptionServiceError.\(expectedError)")
    } catch let error as OpenAITranscriptionServiceError {
        #expect(error == expectedError)
    } catch {
        Issue.record("Expected OpenAITranscriptionServiceError, got \(error)")
    }
}

private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: OpenAITranscriptionRequestBuilder.defaultEndpointURL,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private final class FakeAPIKeyStorage: APIKeyStorage {
    private let apiKey: String?
    private let loadError: Error?

    init(apiKey: String? = "sk-test", loadError: Error? = nil) {
        self.apiKey = apiKey
        self.loadError = loadError
    }

    func saveAPIKey(_ apiKey: String) throws {}

    func loadAPIKey() throws -> String? {
        if let loadError {
            throw loadError
        }

        return apiKey
    }

    func deleteAPIKey() throws {}
}

private final class FakeURLLoader: URLLoading {
    enum Result {
        case success(Data, URLResponse)
        case delayedSuccess(Data, URLResponse)
        case failure(Error)
    }

    private let result: Result
    private(set) var requests: [URLRequest] = []

    init(result: Result) {
        self.result = result
    }

    func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)

        switch result {
        case let .success(data, response):
            return (data, response)
        case let .delayedSuccess(data, response):
            try await Task.sleep(nanoseconds: 1_000_000_000)
            return (data, response)
        case let .failure(error):
            throw error
        }
    }
}

private final class FakeTimeoutSleeper: TranscriptionTimeoutSleeping {
    enum Mode {
        case waitForCancellation
        case timeoutImmediately
    }

    private let mode: Mode
    private(set) var sleepCalls: [TimeInterval] = []

    init(mode: Mode = .waitForCancellation) {
        self.mode = mode
    }

    func sleep(seconds: TimeInterval) async throws {
        sleepCalls.append(seconds)

        switch mode {
        case .waitForCancellation:
            try await Task.sleep(nanoseconds: 1_000_000_000)
        case .timeoutImmediately:
            return
        }
    }
}
