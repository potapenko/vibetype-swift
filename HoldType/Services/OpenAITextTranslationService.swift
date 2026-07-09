//
//  OpenAITextTranslationService.swift
//  HoldType
//
//  Created by Codex on 7/5/26.
//

import Foundation
import HoldTypeDomain

protocol OpenAITextTranslationServing {
    func translate(
        _ transcript: String,
        settings: AppSettings,
        credential: OpenAICredential
    ) async throws -> String
    func cancelActiveTranslation()
}

extension OpenAITextTranslationServing {
    func cancelActiveTranslation() {}
}

struct OpenAITextTranslationService: OpenAITextTranslationServing {
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

    init(
        endpointURL: URL = Self.defaultEndpointURL,
        urlLoader: any URLLoading = URLSession.shared,
        timeoutSleeper: any TranscriptionTimeoutSleeping = TaskTranscriptionTimeoutSleeper(),
        requestTimeout: TimeInterval = Self.defaultRequestTimeout,
        maxOutputTokens: Int = Self.defaultMaxOutputTokens,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.endpointURL = endpointURL
        self.urlLoader = urlLoader
        self.timeoutSleeper = timeoutSleeper
        self.requestTimeout = requestTimeout > 0 ? requestTimeout : Self.defaultRequestTimeout
        self.maxOutputTokens = max(1, maxOutputTokens)
        self.encoder = encoder
        self.decoder = decoder
    }

    func translate(
        _ transcript: String,
        settings: AppSettings,
        credential: OpenAICredential
    ) async throws -> String {
        let inputText = try normalizedInputText(from: transcript)
        var request = try makeAuthorizedRequest(
            inputText: inputText,
            settings: settings,
            credential: credential
        )
        request.timeoutInterval = requestTimeout

        let (data, response) = try await loadWithTimeout(request)
        try validateHTTPResponse(response)
        return try parseTranslation(from: data)
    }

    private func normalizedInputText(from transcript: String) throws -> String {
        guard let inputText = AcceptedTranscript.nonEmptyNormalizedText(from: transcript) else {
            throw OpenAITextTranslationServiceError.emptyTranslation
        }

        return inputText
    }

    private func makeAuthorizedRequest(
        inputText: String,
        settings: AppSettings,
        credential: OpenAICredential
    ) throws -> URLRequest {
        let instructions = try makeInstructions(settings: settings)

        do {
            let payload = OpenAITextTranslationRequest(
                model: settings.resolvedTranslationModel,
                instructions: instructions,
                input: [
                    OpenAITextTranslationInputMessage(
                        role: "user",
                        content: [
                            OpenAITextTranslationInputContent(
                                type: "input_text",
                                text: inputText
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

    private func makeInstructions(settings: AppSettings) throws -> String {
        guard settings.isTranslationSourceConfigurationValid,
              let targetCode = settings.resolvedTranslationTargetLanguageCode else {
            throw OpenAITextTranslationServiceError.invalidLanguageConfiguration
        }

        let routeInstruction: String
        if let sourceCode = settings.resolvedTranslationSourceLanguageCode {
            routeInstruction = "Translate from language code \(sourceCode) to language code \(targetCode)."
        } else {
            routeInstruction = "Translate the user's transcript to language code \(targetCode)."
        }

        return """
        \(routeInstruction)
        Return only the translated text.

        User translation instructions:
        \(settings.resolvedTranslationPrompt)
        """
    }

    private func loadWithTimeout(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await withThrowingTaskGroup(of: TextTranslationURLLoadResult.self) { group in
                group.addTask {
                    let (data, response) = try await urlLoader.loadData(for: request)
                    return TextTranslationURLLoadResult(data: data, response: response)
                }

                group.addTask {
                    try await timeoutSleeper.sleep(seconds: requestTimeout)
                    throw OpenAITextTranslationServiceError.timedOut
                }

                guard let result = try await group.next() else {
                    throw OpenAITextTranslationServiceError.invalidResponse
                }

                group.cancelAll()
                return (result.data, result.response)
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

enum OpenAITextTranslationServiceError: Error, Equatable, LocalizedError {
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

    var errorDescription: String? {
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

private struct TextTranslationURLLoadResult {
    let data: Data
    let response: URLResponse
}
