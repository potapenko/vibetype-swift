//
//  OpenAITextCorrectionService.swift
//  HoldType
//
//  Created by Codex on 7/5/26.
//

import Foundation
import HoldTypeDomain

public protocol OpenAITextCorrectionServing {
    func correct(
        _ transcript: AcceptedTranscript,
        configuration: TextCorrectionConfiguration,
        credential: OpenAICredential
    ) async throws -> String
    func cancelActiveCorrection()
}

public extension OpenAITextCorrectionServing {
    func cancelActiveCorrection() {}
}

public struct OpenAITextCorrectionService: OpenAITextCorrectionServing, Sendable {
    static let defaultEndpointURL = URL(string: "https://api.openai.com/v1/responses")!
    static let defaultRequestTimeout: TimeInterval = 20
    static let defaultMaxOutputTokens = 4096

    private let endpointURL: URL
    private let urlLoader: any URLLoading
    private let timeoutSleeper: any TranscriptionTimeoutSleeping
    private let requestTimeout: TimeInterval
    private let maxOutputTokens: Int
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let requestTaskCoordinator: OpenAIRequestTaskCoordinator

    public init() {
        self.init(
            endpointURL: Self.defaultEndpointURL,
            urlLoader: URLSession.shared,
            timeoutSleeper: TaskTranscriptionTimeoutSleeper(),
            requestTimeout: Self.defaultRequestTimeout,
            maxOutputTokens: Self.defaultMaxOutputTokens,
            encoder: JSONEncoder(),
            decoder: JSONDecoder(),
            requestTaskCoordinator: OpenAIRequestTaskCoordinator()
        )
    }

    init(
        endpointURL: URL,
        urlLoader: any URLLoading = URLSession.shared,
        timeoutSleeper: any TranscriptionTimeoutSleeping = TaskTranscriptionTimeoutSleeper(),
        requestTimeout: TimeInterval = Self.defaultRequestTimeout,
        maxOutputTokens: Int = Self.defaultMaxOutputTokens,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        requestTaskCoordinator: OpenAIRequestTaskCoordinator = OpenAIRequestTaskCoordinator()
    ) {
        self.endpointURL = endpointURL
        self.urlLoader = urlLoader
        self.timeoutSleeper = timeoutSleeper
        self.requestTimeout = requestTimeout > 0 ? requestTimeout : Self.defaultRequestTimeout
        self.maxOutputTokens = max(1, maxOutputTokens)
        self.encoder = encoder
        self.decoder = decoder
        self.requestTaskCoordinator = requestTaskCoordinator
    }

    public func correct(
        _ transcript: AcceptedTranscript,
        configuration: TextCorrectionConfiguration,
        credential: OpenAICredential
    ) async throws -> String {
        var request = try makeAuthorizedRequest(
            inputText: transcript.text,
            configuration: configuration,
            credential: credential
        )
        request.timeoutInterval = requestTimeout

        let (data, response) = try await loadWithTimeout(request)
        try validateHTTPResponse(response)
        return try parseCorrection(from: data)
    }

    public func cancelActiveCorrection() {
        requestTaskCoordinator.cancelActiveRequest()
    }

    private func makeAuthorizedRequest(
        inputText: String,
        configuration: TextCorrectionConfiguration,
        credential: OpenAICredential
    ) throws -> URLRequest {
        do {
            let payload = OpenAITextCorrectionRequest(
                model: configuration.resolvedModel,
                instructions: configuration.resolvedPrompt,
                input: [
                    OpenAITextCorrectionInputMessage(
                        role: "user",
                        content: [
                            OpenAITextCorrectionInputContent(
                                type: "input_text",
                                text: inputText
                            )
                        ]
                    )
                ],
                reasoning: OpenAITextCorrectionReasoning(effort: "low"),
                text: OpenAITextCorrectionTextConfig(
                    format: OpenAITextCorrectionTextFormat(type: "text"),
                    verbosity: "low"
                ),
                toolChoice: "none",
                maxOutputTokens: maxOutputTokens,
                store: false
            )

            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(credential.apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try encoder.encode(payload)
            return request
        } catch {
            throw OpenAITextCorrectionServiceError.invalidRequest
        }
    }

    private func loadWithTimeout(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await requestTaskCoordinator.perform {
                try await urlLoader.loadData(for: request)
            } deadline: {
                try await timeoutSleeper.sleep(seconds: requestTimeout)
                throw OpenAITextCorrectionServiceError.timedOut
            }
        } catch let error as OpenAITextCorrectionServiceError {
            throw error
        } catch let error as URLError {
            throw Self.mapURLError(error)
        } catch is CancellationError {
            throw OpenAITextCorrectionServiceError.cancelled
        } catch {
            throw OpenAITextCorrectionServiceError.networkFailure
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITextCorrectionServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw OpenAITextCorrectionServiceError.invalidAPIKey
        case 408:
            throw OpenAITextCorrectionServiceError.timedOut
        case 429:
            throw OpenAITextCorrectionServiceError.rateLimited
        case 400, 404, 413, 415, 422:
            throw OpenAITextCorrectionServiceError.badRequest
        case 500..<600:
            throw OpenAITextCorrectionServiceError.providerUnavailable
        default:
            throw OpenAITextCorrectionServiceError.providerRejected(statusCode: httpResponse.statusCode)
        }
    }

    private func parseCorrection(from data: Data) throws -> String {
        do {
            let response = try decoder.decode(OpenAITextCorrectionResponse.self, from: data)
            let outputText = response.outputText ?? response.firstOutputText
            return try AcceptedTranscript(rawText: outputText ?? "").text
        } catch AcceptedTranscript.ValidationError.emptyText {
            throw OpenAITextCorrectionServiceError.emptyCorrection
        } catch let error as OpenAITextCorrectionServiceError {
            throw error
        } catch {
            throw OpenAITextCorrectionServiceError.invalidResponse
        }
    }

    private static func mapURLError(_ error: URLError) -> OpenAITextCorrectionServiceError {
        switch error.code {
        case .timedOut:
            return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return .networkUnavailable
        case .cancelled:
            return .cancelled
        default:
            return .networkFailure
        }
    }
}

public enum OpenAITextCorrectionServiceError: Error, Equatable, LocalizedError, Sendable {
    case missingAPIKey
    case apiKeyUnavailable
    case invalidRequest
    case timedOut
    case networkUnavailable
    case networkFailure
    case cancelled
    case invalidAPIKey
    case rateLimited
    case providerUnavailable
    case badRequest
    case providerRejected(statusCode: Int)
    case invalidResponse
    case emptyCorrection

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Enter an OpenAI API key before correcting text."
        case .apiKeyUnavailable:
            return "The OpenAI API key could not be read."
        case .invalidRequest:
            return "The text correction request could not be prepared."
        case .timedOut:
            return "Text correction timed out."
        case .networkUnavailable:
            return "The network is unavailable. Text correction was skipped."
        case .networkFailure:
            return "The text correction request failed."
        case .cancelled:
            return "Text correction was cancelled."
        case .invalidAPIKey:
            return "OpenAI rejected the saved API key. Check Settings."
        case .rateLimited:
            return "OpenAI rate limits were reached. Text correction was skipped."
        case .providerUnavailable:
            return "OpenAI is unavailable. Text correction was skipped."
        case .badRequest:
            return "Text correction settings need attention."
        case .providerRejected:
            return "OpenAI rejected the text correction request."
        case .invalidResponse:
            return "OpenAI returned an unreadable text correction response."
        case .emptyCorrection:
            return "Text correction returned no usable text."
        }
    }
}

private struct OpenAITextCorrectionRequest: Encodable {
    let model: String
    let instructions: String
    let input: [OpenAITextCorrectionInputMessage]
    let reasoning: OpenAITextCorrectionReasoning
    let text: OpenAITextCorrectionTextConfig
    let toolChoice: String
    let maxOutputTokens: Int
    let store: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case reasoning
        case text
        case toolChoice = "tool_choice"
        case maxOutputTokens = "max_output_tokens"
        case store
    }
}

private struct OpenAITextCorrectionInputMessage: Encodable {
    let role: String
    let content: [OpenAITextCorrectionInputContent]
}

private struct OpenAITextCorrectionInputContent: Encodable {
    let type: String
    let text: String
}

private struct OpenAITextCorrectionReasoning: Encodable {
    let effort: String
}

private struct OpenAITextCorrectionTextConfig: Encodable {
    let format: OpenAITextCorrectionTextFormat
    let verbosity: String
}

private struct OpenAITextCorrectionTextFormat: Encodable {
    let type: String
}

private struct OpenAITextCorrectionResponse: Decodable {
    let outputText: String?
    let output: [OpenAITextCorrectionOutputItem]?

    var firstOutputText: String? {
        output?
            .compactMap { item in
                item.content?.first { $0.type == "output_text" }?.text
            }
            .first
    }

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct OpenAITextCorrectionOutputItem: Decodable {
    let content: [OpenAITextCorrectionOutputContent]?
}

private struct OpenAITextCorrectionOutputContent: Decodable {
    let type: String
    let text: String?
}
