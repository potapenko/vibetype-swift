//
//  OpenAITranscriptionService.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import Foundation

protocol OpenAITranscriptionServing {
    func transcribe(audioFileURL: URL, settings: AppSettings) async throws -> String
}

protocol URLLoading {
    func loadData(for request: URLRequest) async throws -> (Data, URLResponse)
}

protocol TranscriptionTimeoutSleeping {
    func sleep(seconds: TimeInterval) async throws
}

struct OpenAITranscriptionService: OpenAITranscriptionServing {
    static let defaultRequestTimeout: TimeInterval = 60

    private let apiKeyStorage: any APIKeyStorage
    private let requestBuilder: OpenAITranscriptionRequestBuilder
    private let urlLoader: any URLLoading
    private let timeoutSleeper: any TranscriptionTimeoutSleeping
    private let requestTimeout: TimeInterval
    private let decoder: JSONDecoder

    init(
        apiKeyStorage: any APIKeyStorage = KeychainService(),
        requestBuilder: OpenAITranscriptionRequestBuilder = OpenAITranscriptionRequestBuilder(),
        urlLoader: any URLLoading = URLSession.shared,
        timeoutSleeper: any TranscriptionTimeoutSleeping = TaskTranscriptionTimeoutSleeper(),
        requestTimeout: TimeInterval = Self.defaultRequestTimeout,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.apiKeyStorage = apiKeyStorage
        self.requestBuilder = requestBuilder
        self.urlLoader = urlLoader
        self.timeoutSleeper = timeoutSleeper
        self.requestTimeout = requestTimeout > 0 ? requestTimeout : Self.defaultRequestTimeout
        self.decoder = decoder
    }

    func transcribe(audioFileURL: URL, settings: AppSettings) async throws -> String {
        let apiKey = try loadAPIKey()
        var request = try makeAuthorizedRequest(
            audioFileURL: audioFileURL,
            settings: settings,
            apiKey: apiKey
        )

        request.timeoutInterval = requestTimeout

        let (data, response) = try await loadWithTimeout(request)
        try validateHTTPResponse(response)
        return try parseTranscript(from: data, settings: settings)
    }

    private func loadAPIKey() throws -> String {
        do {
            guard let apiKey = try apiKeyStorage.loadAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !apiKey.isEmpty else {
                throw OpenAITranscriptionServiceError.missingAPIKey
            }

            return apiKey
        } catch let error as OpenAITranscriptionServiceError {
            throw error
        } catch {
            throw OpenAITranscriptionServiceError.apiKeyUnavailable
        }
    }

    private func makeAuthorizedRequest(
        audioFileURL: URL,
        settings: AppSettings,
        apiKey: String
    ) throws -> URLRequest {
        do {
            var request = try requestBuilder.makeRequest(audioFileURL: audioFileURL, settings: settings)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            return request
        } catch let error as OpenAITranscriptionRequestBuilderError {
            throw OpenAITranscriptionServiceError.invalidRecording(error)
        } catch {
            throw OpenAITranscriptionServiceError.invalidRequest
        }
    }

    private func loadWithTimeout(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await withThrowingTaskGroup(of: URLLoadResult.self) { group in
                group.addTask {
                    let (data, response) = try await urlLoader.loadData(for: request)
                    return URLLoadResult(data: data, response: response)
                }

                group.addTask {
                    try await timeoutSleeper.sleep(seconds: requestTimeout)
                    throw OpenAITranscriptionServiceError.timedOut
                }

                guard let result = try await group.next() else {
                    throw OpenAITranscriptionServiceError.invalidResponse
                }

                group.cancelAll()
                return (result.data, result.response)
            }
        } catch let error as OpenAITranscriptionServiceError {
            throw error
        } catch let error as URLError {
            throw Self.mapURLError(error)
        } catch is CancellationError {
            throw OpenAITranscriptionServiceError.cancelled
        } catch {
            throw OpenAITranscriptionServiceError.networkFailure
        }
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITranscriptionServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw OpenAITranscriptionServiceError.invalidAPIKey
        case 408:
            throw OpenAITranscriptionServiceError.timedOut
        case 429:
            throw OpenAITranscriptionServiceError.rateLimited
        case 400, 404, 413, 415, 422:
            throw OpenAITranscriptionServiceError.badRequest
        case 500..<600:
            throw OpenAITranscriptionServiceError.providerUnavailable
        default:
            throw OpenAITranscriptionServiceError.providerRejected(statusCode: httpResponse.statusCode)
        }
    }

    private func parseTranscript(from data: Data, settings: AppSettings) throws -> String {
        do {
            let response = try decoder.decode(OpenAITranscriptionResponse.self, from: data)
            let transcript = try AcceptedTranscript(rawText: response.text).text
            guard !DictionaryEchoFilter.matches(
                transcript: transcript,
                dictionaryPrompt: settings.resolvedCustomDictionaryPrompt
            ) else {
                throw OpenAITranscriptionServiceError.dictionaryEcho
            }

            return transcript
        } catch AcceptedTranscript.ValidationError.emptyText {
            throw OpenAITranscriptionServiceError.emptyTranscript
        } catch let error as OpenAITranscriptionServiceError {
            throw error
        } catch {
            throw OpenAITranscriptionServiceError.invalidResponse
        }
    }

    private static func mapURLError(_ error: URLError) -> OpenAITranscriptionServiceError {
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

struct DictionaryEchoFilter {
    static func matches(transcript: String?, dictionaryPrompt: String?) -> Bool {
        guard let transcript, let dictionaryPrompt else {
            return false
        }

        let transcriptWords = Set(normalizedWords(in: transcript))
        let dictionaryWords = Set(normalizedWords(in: dictionaryPrompt))
        guard !transcriptWords.isEmpty, !dictionaryWords.isEmpty else {
            return false
        }

        let matchingWordCount = transcriptWords.intersection(dictionaryWords).count
        let textComposition = Double(matchingWordCount) / Double(transcriptWords.count)
        let dictionaryUsage = Double(matchingWordCount) / Double(dictionaryWords.count)

        return textComposition >= 0.9 && dictionaryUsage >= 0.7
    }

    private static func normalizedWords(in text: String) -> [String] {
        var scalars = String.UnicodeScalarView()
        let space = UnicodeScalar(" ")

        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
            } else {
                scalars.append(space)
            }
        }

        return String(scalars).split(separator: " ").map(String.init)
    }
}

extension URLSession: URLLoading {
    func loadData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

struct TaskTranscriptionTimeoutSleeper: TranscriptionTimeoutSleeping {
    func sleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

enum OpenAITranscriptionServiceError: Error, Equatable, LocalizedError {
    case missingAPIKey
    case apiKeyUnavailable
    case invalidRecording(OpenAITranscriptionRequestBuilderError)
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
    case emptyTranscript
    case dictionaryEcho

    var errorDescription: String? {
        userFacingMessage
    }

    var userFacingMessage: String {
        switch self {
        case .missingAPIKey:
            return "Enter an OpenAI API key before transcribing."
        case .apiKeyUnavailable:
            return "The OpenAI API key could not be read."
        case .invalidRecording(let error):
            return error.userFacingMessage
        case .invalidRequest:
            return "The transcription request could not be prepared."
        case .timedOut:
            return "Transcription timed out."
        case .networkUnavailable:
            return "The network is unavailable. Try again when you are connected."
        case .networkFailure:
            return "The transcription request failed. Try again."
        case .cancelled:
            return "Transcription was cancelled."
        case .invalidAPIKey:
            return "OpenAI rejected the saved API key. Check Settings."
        case .rateLimited:
            return "OpenAI rate limits were reached. Try again later."
        case .providerUnavailable:
            return "OpenAI is unavailable. Try again later."
        case .badRequest:
            return "Transcription settings or recording format need attention."
        case .providerRejected:
            return "OpenAI rejected the transcription request."
        case .invalidResponse:
            return "OpenAI returned an unreadable transcription response."
        case .emptyTranscript:
            return "No speech text was detected."
        case .dictionaryEcho:
            return "Only dictionary hints were detected."
        }
    }

    var operatorLogCategory: String {
        switch self {
        case .missingAPIKey:
            return "missing_api_key"
        case .apiKeyUnavailable:
            return "api_key_unavailable"
        case .invalidRecording(let error):
            return error.operatorLogCategory
        case .invalidRequest:
            return "invalid_request"
        case .timedOut:
            return "timeout"
        case .networkUnavailable:
            return "network_unavailable"
        case .networkFailure:
            return "network_failure"
        case .cancelled:
            return "cancelled"
        case .invalidAPIKey:
            return "invalid_api_key"
        case .rateLimited:
            return "rate_limited"
        case .providerUnavailable:
            return "provider_unavailable"
        case .badRequest:
            return "bad_request"
        case .providerRejected(let statusCode):
            return "provider_rejected_\(statusCode)"
        case .invalidResponse:
            return "invalid_response"
        case .emptyTranscript:
            return "empty_transcript"
        case .dictionaryEcho:
            return "dictionary_echo"
        }
    }
}

private extension OpenAITranscriptionRequestBuilderError {
    var userFacingMessage: String {
        switch self {
        case .missingAudioFile:
            return "The recording file is missing."
        case .emptyAudioFile:
            return "No audio was captured. Try recording again."
        case .unsupportedAudioFileType:
            return "The recording format is not supported."
        case .unreadableAudioFile:
            return "The recording file could not be read."
        case .invalidCustomLanguageCode:
            return "Use a two- or three-letter custom language code."
        }
    }

    var operatorLogCategory: String {
        switch self {
        case .missingAudioFile:
            return "missing_audio_file"
        case .emptyAudioFile:
            return "empty_audio"
        case .unsupportedAudioFileType:
            return "unsupported_audio"
        case .unreadableAudioFile:
            return "unreadable_audio"
        case .invalidCustomLanguageCode:
            return "invalid_language_code"
        }
    }
}

private struct URLLoadResult {
    let data: Data
    let response: URLResponse
}

private struct OpenAITranscriptionResponse: Decodable {
    let text: String
}
