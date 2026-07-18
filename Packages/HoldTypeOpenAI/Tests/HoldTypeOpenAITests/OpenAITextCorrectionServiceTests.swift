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
