//
//  OpenAITranscriptionServiceTests.swift
//  HoldTypeTests
//
//  Created by Codex on 6/21/26.
//

import Darwin
import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeOpenAI

@MainActor
struct OpenAITranscriptionServiceTests {

    @Test func successfulResponseReturnsTrimmedTranscriptAndAuthorizedRequest() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = FakeURLLoader(
            result: .success(
                Data(#"{"text":"  Hello from HoldType \n"}"#.utf8),
                makeHTTPResponse(statusCode: 200)
            )
        )
        let sleeper = FakeTimeoutSleeper()
        let service = makeService(
            loader: loader,
            sleeper: sleeper,
            requestTimeout: 7
        )

        let transcript = try await service.transcribe(
            try makeTranscriptionRequest(audioFileURL: audioFileURL),
            credential: testCredential("sk-test-secret")
        )

        #expect(transcript == "Hello from HoldType")
        #expect(loader.requests.count == 1)

        let request = try #require(loader.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-secret")
        #expect(request.timeoutInterval == 7)
        let body = try #require(loader.uploadedBodies.first)
        #expect(request.httpBody == nil)
        #expect(request.httpBodyStream == nil)
        #expect(body.contains(Data("sk-test-secret".utf8)) == false)
        #expect(loader.bodyFileURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(sleeper.sleepCalls == [7])
    }

    @Test func boundedTimeoutMapsToUserVisibleTimeoutError() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = ControlledURLLoader(cancellationBehaviors: [.failImmediately])
        let sleeper = RequestStartedProviderTimeoutSleeper(loader: loader)
        let service = makeService(loader: loader, sleeper: sleeper, requestTimeout: 3)

        await expectTranscriptionError(.timedOut) {
            try await service.transcribe(
                try makeTranscriptionRequest(audioFileURL: audioFileURL),
                credential: testCredential()
            )
        }

        #expect(loader.requests.count == 1)
        #expect(loader.requests.first?.timeoutInterval == 3)
        #expect(loader.cancellationCount(forRequestAt: 0) == 1)
        #expect(loader.bodyFileURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func explicitCancellationCancelsTransportAndIsIdempotent() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = ControlledURLLoader(cancellationBehaviors: [.failImmediately])
        let service = makeService(loader: loader)
        let request = try makeTranscriptionRequest(audioFileURL: audioFileURL)
        let credential = try testCredential()

        service.cancelActiveTranscription()
        let transcription = Task {
            try await service.transcribe(request, credential: credential)
        }
        try await loader.waitForRequestCount(1)

        service.cancelActiveTranscription()
        service.cancelActiveTranscription()

        await expectTranscriptionError(.cancelled) {
            try await transcription.value
        }
        try await loader.waitForCancellation(ofRequestAt: 0)
        #expect(loader.cancellationCount(forRequestAt: 0) == 1)
        #expect(loader.bodyFileURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })

        service.cancelActiveTranscription()
        #expect(loader.cancellationCount(forRequestAt: 0) == 1)
    }

    @Test func explicitCancellationCompletesBeforeNonCooperativeLoaderReturns() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = ControlledURLLoader(cancellationBehaviors: [.awaitResponse])
        let service = makeService(loader: loader)
        let resultProbe = AsyncOperationResultProbe<String>()
        let lateResponse = makeHTTPResponse(statusCode: 200)
        defer {
            loader.resolveRequest(
                at: 0,
                data: Data(#"{"text":"late transcript"}"#.utf8),
                response: lateResponse
            )
        }

        let transcription = Task {
            do {
                let result = try await service.transcribe(
                    try makeTranscriptionRequest(audioFileURL: audioFileURL),
                    credential: testCredential()
                )
                resultProbe.complete(with: .success(result))
            } catch {
                resultProbe.complete(with: .failure(error))
            }
        }
        try await loader.waitForRequestCount(1)

        service.cancelActiveTranscription()

        try await loader.waitForCancellation(ofRequestAt: 0)
        let result = try await resultProbe.waitForResult()
        switch result {
        case .success:
            Issue.record("Expected cancellation before the loader returned.")
        case let .failure(error as OpenAITranscriptionServiceError):
            #expect(error == .cancelled)
        case let .failure(error):
            Issue.record("Expected OpenAITranscriptionServiceError.cancelled, got \(error)")
        }
        #expect(loader.bodyFileURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        await transcription.value
    }

    @Test func cancelledLateLoaderResponseCannotBecomeTranscript() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = ControlledURLLoader(cancellationBehaviors: [.awaitResponse])
        let service = makeService(loader: loader)
        let request = try makeTranscriptionRequest(audioFileURL: audioFileURL)
        let credential = try testCredential()
        let transcription = Task {
            try await service.transcribe(request, credential: credential)
        }
        try await loader.waitForRequestCount(1)

        service.cancelActiveTranscription()
        try await loader.waitForCancellation(ofRequestAt: 0)
        loader.resolveRequest(
            at: 0,
            data: Data(#"{"text":"late transcript"}"#.utf8),
            response: makeHTTPResponse(statusCode: 200)
        )

        await expectTranscriptionError(.cancelled) {
            try await transcription.value
        }
    }

    @Test func parentTaskCancellationCancelsTransport() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = ControlledURLLoader(cancellationBehaviors: [.failImmediately])
        let service = makeService(loader: loader)
        let request = try makeTranscriptionRequest(audioFileURL: audioFileURL)
        let credential = try testCredential()
        let transcription = Task {
            try await service.transcribe(request, credential: credential)
        }
        try await loader.waitForRequestCount(1)

        transcription.cancel()

        await expectTranscriptionError(.cancelled) {
            try await transcription.value
        }
        try await loader.waitForCancellation(ofRequestAt: 0)
        #expect(loader.cancellationCount(forRequestAt: 0) == 1)
        #expect(loader.bodyFileURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func timeoutCancelsTransportWithoutChangingTimeoutError() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = ControlledURLLoader(cancellationBehaviors: [.failImmediately])
        let service = makeService(
            loader: loader,
            sleeper: RequestStartedProviderTimeoutSleeper(loader: loader),
            requestTimeout: 3
        )

        await expectTranscriptionError(.timedOut) {
            try await service.transcribe(
                try makeTranscriptionRequest(audioFileURL: audioFileURL),
                credential: testCredential()
            )
        }

        try await loader.waitForRequestCount(1)
        try await loader.waitForCancellation(ofRequestAt: 0)
        #expect(loader.cancellationCount(forRequestAt: 0) == 1)
        #expect(loader.bodyFileURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func timeoutCompletesBeforeNonCooperativeLoaderReturns() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = ControlledURLLoader(cancellationBehaviors: [.awaitResponse])
        let sleeper = RequestStartedProviderTimeoutSleeper(loader: loader)
        let service = makeService(
            loader: loader,
            sleeper: sleeper,
            requestTimeout: 3
        )
        let resultProbe = AsyncOperationResultProbe<String>()
        let lateResponse = makeHTTPResponse(statusCode: 200)
        defer {
            loader.resolveRequest(
                at: 0,
                data: Data(#"{"text":"late transcript"}"#.utf8),
                response: lateResponse
            )
        }

        let transcription = Task {
            do {
                let result = try await service.transcribe(
                    try makeTranscriptionRequest(audioFileURL: audioFileURL),
                    credential: testCredential()
                )
                resultProbe.complete(with: .success(result))
            } catch {
                resultProbe.complete(with: .failure(error))
            }
        }
        try await loader.waitForRequestCount(1)

        try await loader.waitForCancellation(ofRequestAt: 0)
        let result = try await resultProbe.waitForResult()
        switch result {
        case .success:
            Issue.record("Expected timeout before the loader returned.")
        case let .failure(error as OpenAITranscriptionServiceError):
            #expect(error == .timedOut)
        case let .failure(error):
            Issue.record("Expected OpenAITranscriptionServiceError.timedOut, got \(error)")
        }
        #expect(loader.bodyFileURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        await transcription.value
    }

    @Test func cancellationDuringBlockedReadWriteAndSyncCompletesBeforeLocalIO() async throws {
        for stage in BlockingPreparationPOSIXCalls.Stage.allCases {
            try await verifyBlockedPreparation(stage: stage, expectedError: .cancelled)
        }
    }

    @Test func timeoutDuringBlockedReadWriteAndSyncCompletesBeforeLocalIO() async throws {
        for stage in BlockingPreparationPOSIXCalls.Stage.allCases {
            try await verifyBlockedPreparation(stage: stage, expectedError: .timedOut)
        }
    }

    @Test func olderRequestCleanupCannotClearNewerRequestAndNextRequestCanSucceed() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let loader = ControlledURLLoader(
            cancellationBehaviors: [.awaitResponse, .awaitResponse, .failImmediately]
        )
        let service = makeService(loader: loader)
        let request = try makeTranscriptionRequest(audioFileURL: audioFileURL)
        let credential = try testCredential()
        let olderTranscription = Task {
            try await service.transcribe(request, credential: credential)
        }
        try await loader.waitForRequestCount(1)

        let newerTranscription = Task {
            try await service.transcribe(request, credential: credential)
        }
        try await loader.waitForRequestCount(2)
        try await loader.waitForCancellation(ofRequestAt: 0)
        loader.resolveRequest(
            at: 0,
            data: Data(#"{"text":"stale transcript"}"#.utf8),
            response: makeHTTPResponse(statusCode: 200)
        )
        await expectTranscriptionError(.cancelled) {
            try await olderTranscription.value
        }

        service.cancelActiveTranscription()
        try await loader.waitForCancellation(ofRequestAt: 1)
        loader.resolveRequest(
            at: 1,
            data: Data(#"{"text":"also stale"}"#.utf8),
            response: makeHTTPResponse(statusCode: 200)
        )
        await expectTranscriptionError(.cancelled) {
            try await newerTranscription.value
        }

        let finalTranscription = Task {
            try await service.transcribe(request, credential: credential)
        }
        try await loader.waitForRequestCount(3)
        loader.resolveRequest(
            at: 2,
            data: Data(#"{"text":"independent success"}"#.utf8),
            response: makeHTTPResponse(statusCode: 200)
        )

        #expect(try await finalTranscription.value == "independent success")
    }

    @Test func urlSessionTimeoutErrorMapsToUserVisibleTimeoutError() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let service = makeService(loader: FakeURLLoader(result: .failure(URLError(.timedOut))))

        await expectTranscriptionError(.timedOut) {
            try await service.transcribe(
                try makeTranscriptionRequest(audioFileURL: audioFileURL),
                credential: testCredential()
            )
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
                try await service.transcribe(
                    try makeTranscriptionRequest(audioFileURL: audioFileURL),
                    credential: testCredential()
                )
            }
        }
    }

    @Test func boundedFileUploadTransportFailuresMapToProductErrors() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let cases: [(OpenAIFileUploadTransportError, OpenAITranscriptionServiceError)] = [
            (.invalidRequest, .invalidRequest),
            (.invalidResponse, .invalidResponse),
            (.responseTooLarge, .invalidResponse),
            (.redirectRejected, .invalidResponse),
            (.cancelled, .cancelled),
            (.transportFailure, .networkFailure),
        ]

        for (transportError, expectedError) in cases {
            let loader = FakeURLLoader(result: .failure(transportError))
            let service = makeService(loader: loader)

            await expectTranscriptionError(expectedError) {
                try await service.transcribe(
                    try makeTranscriptionRequest(audioFileURL: audioFileURL),
                    credential: testCredential()
                )
            }

            #expect(loader.bodyFileURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        }
    }

    @Test func lateUploadBodyFailureMapsToLocalInvalidRequestNotNetworkFailure() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }
        let loader = FakeURLLoader(
            result: .failure(
                OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
            )
        )
        let service = makeService(loader: loader)

        await expectTranscriptionError(.invalidRequest) {
            try await service.transcribe(
                try makeTranscriptionRequest(audioFileURL: audioFileURL),
                credential: testCredential()
            )
        }

        #expect(loader.requests.count == 1)
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
                try await service.transcribe(
                    try makeTranscriptionRequest(audioFileURL: audioFileURL),
                    credential: testCredential()
                )
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
            try await service.transcribe(
                try makeTranscriptionRequest(audioFileURL: audioFileURL),
                credential: testCredential()
            )
        }
    }

    @Test func dictionaryEchoTranscriptIsRejected() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let service = makeService(
            loader: FakeURLLoader(
                result: .success(
                    Data(#"{"text":"OpenWhispr, Parakeet, Alcahest."}"#.utf8),
                    makeHTTPResponse(statusCode: 200)
                )
            )
        )

        await expectTranscriptionError(.dictionaryEcho) {
            try await service.transcribe(
                try makeTranscriptionRequest(
                    audioFileURL: audioFileURL,
                    customDictionary: CustomDictionary(
                        entries: ["OpenWhispr", "Parakeet", "Alcahest"]
                    )
                ),
                credential: testCredential()
            )
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

    @Test func activeTextContextEchoTranscriptIsRejected() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let context = try #require(
            TranscriptionPromptContext("We are already writing about contextual dictation quality.")
        )
        let service = makeService(
            loader: FakeURLLoader(
                result: .success(
                    Data(#"{"text":"already writing about contextual dictation"}"#.utf8),
                    makeHTTPResponse(statusCode: 200)
                )
            )
        )

        await expectTranscriptionError(.contextEcho) {
            try await service.transcribe(
                try makeTranscriptionRequest(
                    audioFileURL: audioFileURL,
                    context: context
                ),
                credential: testCredential()
            )
        }
    }

    @Test func disabledNearbyContextIsAbsentFromPromptAndEchoGuard() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let context = try #require(
            TranscriptionPromptContext("We are already writing about contextual dictation quality.")
        )
        let loader = FakeURLLoader(
            result: .success(
                Data(#"{"text":"already writing about contextual dictation"}"#.utf8),
                makeHTTPResponse(statusCode: 200)
            )
        )
        let service = makeService(loader: loader)

        let transcript = try await service.transcribe(
            try makeTranscriptionRequest(
                audioFileURL: audioFileURL,
                emojiCommandsConfiguration: EmojiCommandsConfiguration(isEnabled: false)
            ),
            credential: testCredential()
        )

        #expect(transcript == "already writing about contextual dictation")
        let body = try #require(loader.uploadedBodies.first)
        let bodyText = try #require(String(data: body, encoding: .utf8))
        #expect(bodyText.contains(context.text) == false)
    }

    @Test func activeTextContextEchoFilterDistinguishesEchoFromLegitimateSpeech() {
        #expect(
            ActiveTextContextEchoFilter.matches(
                transcript: "already writing about contextual dictation",
                contextText: "We are already writing about contextual dictation quality."
            )
        )
        #expect(
            ActiveTextContextEchoFilter.matches(
                transcript: "contextual dictation quality is better now",
                contextText: "We are already writing about contextual dictation quality."
            ) == false
        )
        #expect(
            ActiveTextContextEchoFilter.matches(
                transcript: "contextual dictation",
                contextText: "We are already writing about contextual dictation quality."
            ) == false
        )
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
            try await service.transcribe(
                try makeTranscriptionRequest(audioFileURL: audioFileURL),
                credential: testCredential()
            )
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
            try await service.transcribe(
                try makeTranscriptionRequest(audioFileURL: audioFileURL),
                credential: testCredential()
            )
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
            try await service.transcribe(
                try makeTranscriptionRequest(audioFileURL: audioFileURL),
                credential: testCredential()
            )
        }

        #expect(loader.requests.isEmpty)
    }

    @Test func oversizedMultipartMetadataIsMappedBeforeScratchUpload() async throws {
        let audioFileURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }
        let transcriptionConfiguration = TranscriptionConfiguration(
            freeformPrompt: String(
                repeating: "x",
                count: Int(OpenAITranscriptionRequestBuilder.maximumMetadataByteCount)
            )
        )
        let loader = FakeURLLoader(
            result: .success(Data(#"{"text":"unused"}"#.utf8), makeHTTPResponse(statusCode: 200))
        )
        let service = makeService(loader: loader)

        await expectTranscriptionError(.multipartMetadataTooLarge) {
            try await service.transcribe(
                try makeTranscriptionRequest(
                    audioFileURL: audioFileURL,
                    transcriptionConfiguration: transcriptionConfiguration
                ),
                credential: testCredential()
            )
        }

        #expect(loader.requests.isEmpty)
        #expect(loader.bodyFileURLs.isEmpty)
    }

    @Test func invalidCustomLanguageFailsDuringRequestConstructionBeforeServiceFileIO() {
        let missingFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holdtype-invalid-language-\(UUID().uuidString).m4a")
        let transcriptionConfiguration = TranscriptionConfiguration(
            language: .custom,
            customLanguageCode: "en-US"
        )

        #expect(
            throws: AudioTranscriptionRequest.ValidationError.invalidCustomLanguageCode("en-US")
        ) {
            _ = try makeTranscriptionRequest(
                audioFileURL: missingFileURL,
                transcriptionConfiguration: transcriptionConfiguration
            )
        }
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
                "OpenAI rejected the saved API key.",
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
                .multipartMetadataTooLarge,
                "The transcription request settings are too large.",
                "multipart_metadata_too_large"
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
            (
                .contextEcho,
                "Only nearby context was detected.",
                "context_echo"
            ),
        ]

        for (error, expectedMessage, expectedLogCategory) in cases {
            #expect(error.userFacingMessage == expectedMessage)
            #expect(error.errorDescription == expectedMessage)
            #expect(error.operatorLogCategory == expectedLogCategory)
        }

        let secretURL = URL(fileURLWithPath: "/private/source-sentinel.m4a")
        let secretError = OpenAITranscriptionServiceError.invalidRecording(
            .unreadableAudioFile(secretURL)
        )
        var dumpText = ""
        dump(secretError, to: &dumpText)
        for value in [String(reflecting: secretError), dumpText] {
            #expect(!value.contains("source-sentinel"))
        }
    }

    private func makeTranscriptionRequest(
        audioFileURL: URL,
        transcriptionConfiguration: TranscriptionConfiguration = .defaults,
        context: TranscriptionPromptContext? = nil,
        emojiCommandsConfiguration: EmojiCommandsConfiguration = .defaults,
        customDictionary: CustomDictionary = .empty
    ) throws -> AudioTranscriptionRequest {
        try AudioTranscriptionRequest(
            audioFileURL: audioFileURL,
            transcriptionConfiguration: transcriptionConfiguration,
            promptComposition: TranscriptionPromptComposition(
                resolvedFreeformPrompt: transcriptionConfiguration.resolvedFreeformPrompt,
                context: context,
                emojiCommandsConfiguration: emojiCommandsConfiguration,
                customDictionary: customDictionary
            )
        )
    }

    private func makeService(
        loader: any URLFileUploading,
        sleeper: any TranscriptionTimeoutSleeping = FakeTimeoutSleeper(),
        requestTimeout: TimeInterval = 7,
        requestBuilder: OpenAITranscriptionRequestBuilder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Test"
        )
    ) -> OpenAITranscriptionService {
        OpenAITranscriptionService(
            requestBuilder: requestBuilder,
            urlUploader: loader,
            timeoutSleeper: sleeper,
            requestTimeout: requestTimeout
        )
    }

    private func verifyBlockedPreparation(
        stage: BlockingPreparationPOSIXCalls.Stage,
        expectedError: OpenAITranscriptionServiceError
    ) async throws {
        let sourceData = Data(repeating: 0x41, count: 128 * 1024)
        let audioFileURL = try makeTemporaryAudioFile(contents: sourceData)
        let scratchDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-blocked-preparation-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: scratchDirectory)
        }

        let calls = BlockingPreparationPOSIXCalls(stage: stage)
        defer { calls.release() }
        let loader = FakeURLLoader(
            result: .success(
                Data(#"{"text":"must not be reached"}"#.utf8),
                makeHTTPResponse(statusCode: 200)
            )
        )
        let sleeper: any TranscriptionTimeoutSleeping = expectedError == .timedOut
            ? BlockedPreparationTimeoutSleeper(calls: calls)
            : FakeTimeoutSleeper()
        let service = makeService(
            loader: loader,
            sleeper: sleeper,
            requestTimeout: 3,
            requestBuilder: OpenAITranscriptionRequestBuilder(
                boundary: "Boundary-Blocked-Preparation",
                scratchDirectoryURL: scratchDirectory,
                fileSystem: POSIXOpenAITranscriptionMultipartFileSystem(calls: calls)
            )
        )
        let probe = AsyncOperationResultProbe<String>()
        let transcription = Task {
            do {
                probe.complete(
                    with: .success(
                        try await service.transcribe(
                            try makeTranscriptionRequest(audioFileURL: audioFileURL),
                            credential: testCredential()
                        )
                    )
                )
            } catch {
                probe.complete(with: .failure(error))
            }
        }

        try await calls.waitUntilBlocked()
        if expectedError == .cancelled {
            service.cancelActiveTranscription()
        }
        let result = try await probe.waitForResult()
        switch result {
        case .success:
            Issue.record("Expected \(expectedError) while \(stage) remained blocked.")
        case let .failure(error as OpenAITranscriptionServiceError):
            #expect(error == expectedError)
        case let .failure(error):
            Issue.record("Expected OpenAITranscriptionServiceError, got \(error)")
        }

        try await waitForCondition {
            guard FileManager.default.fileExists(atPath: scratchDirectory.path) else {
                return true
            }
            let names = try? FileManager.default.contentsOfDirectory(
                atPath: scratchDirectory.path
            )
            return names?.contains(where: { $0.hasSuffix(".multipart") }) == false
        }
        let descriptor = try #require(calls.blockedFileDescriptor)
        #expect(Darwin.fcntl(descriptor, F_GETFD) != -1)
        #expect(try Data(contentsOf: audioFileURL) == sourceData)
        #expect(loader.requests.isEmpty)

        calls.release()
        await transcription.value
        try await waitForCondition {
            errno = 0
            return Darwin.fcntl(descriptor, F_GETFD) == -1 && errno == EBADF
        }
    }

    private func testCredential(_ apiKey: String = "sk-test") throws -> OpenAICredential {
        try OpenAICredential(apiKey: apiKey)
    }

    private func makeTemporaryAudioFile(
        named fileName: String = "recording.m4a",
        contents: Data = Data("fake audio bytes".utf8)
    ) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holdtype-transcription-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent(fileName)
        try contents.write(to: fileURL)
        return fileURL
    }
}

@MainActor
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

private func readAllUploadBody(_ body: any OpenAIFileUploadBody) throws -> Data {
    let stream = try body.makeInputStream { _ in }
    stream.open()
    defer { stream.close() }

    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else {
            throw stream.streamError ?? OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        }
        if count == 0 { break }
        result.append(contentsOf: buffer.prefix(count))
    }
    return result
}

private final class FakeURLLoader: URLFileUploading, @unchecked Sendable {
    enum Result {
        case success(Data, URLResponse)
        case failure(Error)
    }

    private let result: Result
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []
    private var storedUploadedBodies: [Data] = []

    var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    var uploadedBodies: [Data] {
        lock.withLock { storedUploadedBodies }
    }

    var bodyFileURLs: [URL] {
        []
    }

    init(result: Result) {
        self.result = result
    }

    func uploadData(
        for request: URLRequest,
        body: any OpenAIFileUploadBody
    ) async throws -> (Data, URLResponse) {
        let uploadedBody = try readAllUploadBody(body)
        lock.withLock {
            storedRequests.append(request)
            storedUploadedBodies.append(uploadedBody)
        }

        switch result {
        case let .success(data, response):
            return (data, response)
        case let .failure(error):
            throw error
        }
    }
}

private final class FakeTimeoutSleeper: TranscriptionTimeoutSleeping, @unchecked Sendable {
    enum Mode {
        case waitForCancellation
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
        }
    }
}

final class ControlledURLLoader: URLFileUploading, URLLoading, @unchecked Sendable {
    enum CancellationBehavior {
        case failImmediately
        case awaitResponse
    }

    private typealias Output = (Data, URLResponse)

    private struct RequestState {
        let cancellationBehavior: CancellationBehavior
        var continuation: CheckedContinuation<Output, Error>?
        var resolvedOutput: Output?
        var cancellationCount = 0
        var isFinished = false
    }

    private enum WaitError: Error {
        case requestCountTimedOut(expected: Int)
        case cancellationTimedOut(requestIndex: Int)
    }

    private let cancellationBehaviors: [CancellationBehavior]
    private let lock = NSLock()
    private var requestStates: [RequestState] = []
    private var storedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    var bodyFileURLs: [URL] {
        []
    }

    init(cancellationBehaviors: [CancellationBehavior]) {
        self.cancellationBehaviors = cancellationBehaviors
    }

    func uploadData(
        for request: URLRequest,
        body: any OpenAIFileUploadBody
    ) async throws -> (Data, URLResponse) {
        _ = try readAllUploadBody(body)
        return try await performRequest(request: request)
    }

    func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await performRequest(request: request)
    }

    private func performRequest(
        request: URLRequest
    ) async throws -> (Data, URLResponse) {
        let requestIndex = registerRequest(request: request)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                registerResponseContinuation(continuation, forRequestAt: requestIndex)
            }
        } onCancel: {
            cancelRequest(at: requestIndex)
        }
    }

    func waitForRequestCount(_ count: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while lock.withLock({ requestStates.count }) < count {
            guard clock.now < deadline else {
                throw WaitError.requestCountTimedOut(expected: count)
            }
            try await clock.sleep(for: .milliseconds(1))
        }
    }

    func waitForCancellation(ofRequestAt requestIndex: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while cancellationCount(forRequestAt: requestIndex) == 0 {
            guard clock.now < deadline else {
                throw WaitError.cancellationTimedOut(requestIndex: requestIndex)
            }
            try await clock.sleep(for: .milliseconds(1))
        }
    }

    func cancellationCount(forRequestAt requestIndex: Int) -> Int {
        lock.withLock {
            guard requestStates.indices.contains(requestIndex) else {
                return 0
            }
            return requestStates[requestIndex].cancellationCount
        }
    }

    func resolveRequest(at requestIndex: Int, data: Data, response: URLResponse) {
        let continuation: CheckedContinuation<Output, Error>? = lock.withLock {
            guard requestStates.indices.contains(requestIndex),
                  !requestStates[requestIndex].isFinished else {
                return nil
            }

            if let continuation = requestStates[requestIndex].continuation {
                requestStates[requestIndex].continuation = nil
                requestStates[requestIndex].isFinished = true
                return continuation
            }

            requestStates[requestIndex].resolvedOutput = (data, response)
            return nil
        }

        continuation?.resume(returning: (data, response))
    }

    private func registerRequest(request: URLRequest) -> Int {
        lock.withLock {
            let requestIndex = requestStates.count
            let behavior = cancellationBehaviors.indices.contains(requestIndex)
                ? cancellationBehaviors[requestIndex]
                : .failImmediately
            requestStates.append(RequestState(cancellationBehavior: behavior))
            storedRequests.append(request)
            return requestIndex
        }
    }

    private func registerResponseContinuation(
        _ continuation: CheckedContinuation<Output, Error>,
        forRequestAt requestIndex: Int
    ) {
        enum ResumeAction {
            case wait
            case returnOutput(Output)
            case throwCancellation
        }

        let action: ResumeAction = lock.withLock {
            guard requestStates.indices.contains(requestIndex) else {
                return .throwCancellation
            }

            if let output = requestStates[requestIndex].resolvedOutput {
                requestStates[requestIndex].resolvedOutput = nil
                requestStates[requestIndex].isFinished = true
                return .returnOutput(output)
            }

            if requestStates[requestIndex].cancellationCount > 0,
               requestStates[requestIndex].cancellationBehavior == .failImmediately {
                requestStates[requestIndex].isFinished = true
                return .throwCancellation
            }

            requestStates[requestIndex].continuation = continuation
            return .wait
        }

        switch action {
        case .wait:
            return
        case .returnOutput(let output):
            continuation.resume(returning: output)
        case .throwCancellation:
            continuation.resume(throwing: CancellationError())
        }
    }

    private func cancelRequest(at requestIndex: Int) {
        let responseContinuation: CheckedContinuation<Output, Error>? = lock.withLock {
            guard requestStates.indices.contains(requestIndex) else {
                return nil
            }

            requestStates[requestIndex].cancellationCount += 1
            if requestStates[requestIndex].cancellationBehavior == .failImmediately,
               !requestStates[requestIndex].isFinished {
                let responseContinuation = requestStates[requestIndex].continuation
                requestStates[requestIndex].continuation = nil
                if responseContinuation != nil {
                    requestStates[requestIndex].isFinished = true
                }
                return responseContinuation
            } else {
                return nil
            }
        }

        responseContinuation?.resume(throwing: CancellationError())
    }
}

private final class BlockingPreparationPOSIXCalls:
    OpenAITranscriptionPOSIXCalling,
    @unchecked Sendable {
    enum Stage: CaseIterable, Sendable {
        case read
        case write
        case synchronize
    }

    private enum WaitError: Error {
        case didNotBlock
    }

    private let stage: Stage
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didBlock = false
    private var didRelease = false
    private var storedFileDescriptor: Int32?

    var blockedFileDescriptor: Int32? {
        lock.withLock { storedFileDescriptor }
    }

    init(stage: Stage) {
        self.stage = stage
    }

    func read(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
        blockIfNeeded(stage: .read, fileDescriptor: fd)
        return Darwin.read(fd, buffer, count)
    }

    func write(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        blockIfNeeded(stage: .write, fileDescriptor: fd)
        return Darwin.write(fd, buffer, count)
    }

    func synchronize(_ fd: Int32) -> Int32 {
        blockIfNeeded(stage: .synchronize, fileDescriptor: fd)
        return Darwin.fsync(fd)
    }

    func pread(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int, _ offset: Int64) -> Int {
        Darwin.pread(fd, buffer, count, off_t(offset))
    }

    func waitUntilBlocked() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !lock.withLock({ didBlock }) {
            guard clock.now < deadline else { throw WaitError.didNotBlock }
            try await clock.sleep(for: .milliseconds(1))
        }
    }

    func release() {
        let shouldSignal = lock.withLock { () -> Bool in
            guard !didRelease else { return false }
            didRelease = true
            return true
        }
        if shouldSignal {
            semaphore.signal()
        }
    }

    private func blockIfNeeded(stage: Stage, fileDescriptor: Int32) {
        let shouldWait = lock.withLock { () -> Bool in
            guard self.stage == stage, !didBlock else { return false }
            didBlock = true
            storedFileDescriptor = fileDescriptor
            return !didRelease
        }
        if shouldWait {
            semaphore.wait()
        }
    }
}

private struct BlockedPreparationTimeoutSleeper: TranscriptionTimeoutSleeping {
    let calls: BlockingPreparationPOSIXCalls

    func sleep(seconds: TimeInterval) async throws {
        try await calls.waitUntilBlocked()
    }
}

private func waitForCondition(
    timeout: Duration = .seconds(1),
    condition: @escaping @Sendable () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            throw OpenAIProviderCancellationTestWaitError.operationDidNotFinish
        }
        try await clock.sleep(for: .milliseconds(1))
    }
}

final class AsyncOperationResultProbe<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func complete(with result: Result<Value, Error>) {
        lock.withLock {
            guard self.result == nil else {
                return
            }
            self.result = result
        }
    }

    func waitForResult() async throws -> Result<Value, Error> {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))

        while true {
            if let result = lock.withLock({ result }) {
                return result
            }
            guard clock.now < deadline else {
                throw OpenAIProviderCancellationTestWaitError.operationDidNotFinish
            }
            try await clock.sleep(for: .milliseconds(1))
        }
    }
}

struct RequestStartedProviderTimeoutSleeper: TranscriptionTimeoutSleeping {
    let loader: ControlledURLLoader

    func sleep(seconds: TimeInterval) async throws {
        try await loader.waitForRequestCount(1)
    }
}

enum OpenAIProviderCancellationTestWaitError: Error {
    case operationDidNotFinish
}
