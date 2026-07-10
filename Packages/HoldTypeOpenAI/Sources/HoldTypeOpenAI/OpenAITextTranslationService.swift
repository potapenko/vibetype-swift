//
//  OpenAITextTranslationService.swift
//  HoldType
//
//  Created by Codex on 7/5/26.
//

import Foundation
import HoldTypeDomain

public protocol OpenAITextTranslationServing {
    func translate(
        _ request: TextTranslationRequest,
        credential: OpenAICredential
    ) async throws -> String
    func cancelActiveTranslation()
}

public extension OpenAITextTranslationServing {
    func cancelActiveTranslation() {}
}

public struct OpenAITextTranslationService: OpenAITextTranslationServing, Sendable {
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

    public func translate(
        _ request: TextTranslationRequest,
        credential: OpenAICredential
    ) async throws -> String {
        var urlRequest = try makeAuthorizedRequest(
            translationRequest: request,
            credential: credential
        )
        urlRequest.timeoutInterval = requestTimeout

        let (data, response) = try await loadWithTimeout(urlRequest)
        try validateHTTPResponse(response)
        return try parseTranslation(from: data)
    }

    public func cancelActiveTranslation() {
        requestTaskCoordinator.cancelActiveRequest()
    }

    private func makeAuthorizedRequest(
        translationRequest: TextTranslationRequest,
        credential: OpenAICredential
    ) throws -> URLRequest {
        let configuration = translationRequest.translationConfiguration
        let instructions = try makeInstructions(request: translationRequest)

        do {
            let payload = OpenAITextTranslationRequest(
                model: configuration.resolvedModel,
                instructions: instructions,
                input: [
                    OpenAITextTranslationInputMessage(
                        role: "user",
                        content: [
                            OpenAITextTranslationInputContent(
                                type: "input_text",
                                text: translationRequest.acceptedTranscript.text
                            )
                        ]
                    )
                ],
                reasoning: OpenAITextTranslationReasoning(effort: "low"),
                text: OpenAITextTranslationTextConfig(
                    format: OpenAITextTranslationTextFormat(type: "text"),
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
        } catch let error as OpenAITextTranslationServiceError {
            throw error
        } catch {
            throw OpenAITextTranslationServiceError.invalidRequest
        }
    }

    private func makeInstructions(request: TextTranslationRequest) throws -> String {
        let configuration = request.translationConfiguration
        guard configuration.isSourceConfigurationValid,
              let targetCode = configuration.resolvedTargetLanguageCode else {
            throw OpenAITextTranslationServiceError.invalidLanguageConfiguration
        }

        let routeInstruction: String
        if let sourceCode = request.resolvedSourceLanguageCode {
            routeInstruction = "Translate from language code \(sourceCode) to language code \(targetCode)."
        } else {
            routeInstruction = "Translate the user's transcript to language code \(targetCode)."
        }

        return """
        \(routeInstruction)
        Return only the translated text.

        User translation instructions:
        \(configuration.resolvedPrompt)
        """
    }

    private func loadWithTimeout(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await requestTaskCoordinator.perform {
                try await urlLoader.loadData(for: request)
            } deadline: {
                try await timeoutSleeper.sleep(seconds: requestTimeout)
                throw OpenAITextTranslationServiceError.timedOut
            }
        } catch let error as OpenAITextTranslationServiceError {
            throw error
        } catch let error as URLError {
            throw Self.mapURLError(error)
        } catch is CancellationError {
            throw OpenAITextTranslationServiceError.cancelled
        } catch {
            throw OpenAITextTranslationServiceError.networkFailure
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITextTranslationServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw OpenAITextTranslationServiceError.invalidAPIKey
        case 408:
            throw OpenAITextTranslationServiceError.timedOut
        case 429:
            throw OpenAITextTranslationServiceError.rateLimited
        case 400, 404, 413, 415, 422:
            throw OpenAITextTranslationServiceError.badRequest
        case 500..<600:
            throw OpenAITextTranslationServiceError.providerUnavailable
        default:
            throw OpenAITextTranslationServiceError.providerRejected(statusCode: httpResponse.statusCode)
        }
    }

    private func parseTranslation(from data: Data) throws -> String {
        do {
            let response = try decoder.decode(OpenAITextTranslationResponse.self, from: data)
            let outputText = response.outputText ?? response.firstOutputText
            return try AcceptedTranscript(rawText: outputText ?? "").text
        } catch AcceptedTranscript.ValidationError.emptyText {
            throw OpenAITextTranslationServiceError.emptyTranslation
        } catch let error as OpenAITextTranslationServiceError {
            throw error
        } catch {
            throw OpenAITextTranslationServiceError.invalidResponse
        }
    }

    private static func mapURLError(_ error: URLError) -> OpenAITextTranslationServiceError {
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

public enum OpenAITextTranslationServiceError: Error, Equatable, LocalizedError, Sendable {
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
    case invalidLanguageConfiguration
    case providerRejected(statusCode: Int)
    case invalidResponse
    case emptyTranslation

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Enter an OpenAI API key before translating text."
        case .apiKeyUnavailable:
            return "The OpenAI API key could not be read."
        case .invalidRequest:
            return "The translation request could not be prepared."
        case .timedOut:
            return "Translation timed out."
        case .networkUnavailable:
            return "The network is unavailable. Translation was not completed."
        case .networkFailure:
            return "The translation request failed."
        case .cancelled:
            return "Translation was cancelled."
        case .invalidAPIKey:
            return "OpenAI rejected the saved API key. Check Settings."
        case .rateLimited:
            return "OpenAI rate limits were reached. Translation was not completed."
        case .providerUnavailable:
            return "OpenAI is unavailable. Translation was not completed."
        case .badRequest:
            return "Translation settings need attention."
        case .invalidLanguageConfiguration:
            return "Choose valid translation languages in Settings."
        case .providerRejected:
            return "OpenAI rejected the translation request."
        case .invalidResponse:
            return "OpenAI returned an unreadable translation response."
        case .emptyTranslation:
            return "Translation returned no usable text."
        }
    }
}

private struct OpenAITextTranslationRequest: Encodable {
    let model: String
    let instructions: String
    let input: [OpenAITextTranslationInputMessage]
    let reasoning: OpenAITextTranslationReasoning
    let text: OpenAITextTranslationTextConfig
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

private struct OpenAITextTranslationInputMessage: Encodable {
    let role: String
    let content: [OpenAITextTranslationInputContent]
}

private struct OpenAITextTranslationInputContent: Encodable {
    let type: String
    let text: String
}

private struct OpenAITextTranslationReasoning: Encodable {
    let effort: String
}

private struct OpenAITextTranslationTextConfig: Encodable {
    let format: OpenAITextTranslationTextFormat
    let verbosity: String
}

private struct OpenAITextTranslationTextFormat: Encodable {
    let type: String
}

private struct OpenAITextTranslationResponse: Decodable {
    let outputText: String?
    let output: [OpenAITextTranslationOutputItem]?

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

private struct OpenAITextTranslationOutputItem: Decodable {
    let content: [OpenAITextTranslationOutputContent]?
}

private struct OpenAITextTranslationOutputContent: Decodable {
    let type: String
    let text: String?
}
