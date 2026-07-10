//
//  OpenAITranscriptionService.swift
//  HoldType
//
//  Created by Codex on 6/21/26.
//

import Foundation
import HoldTypeDomain

public protocol OpenAITranscriptionServing {
    func transcribe(
        _ request: AudioTranscriptionRequest,
        credential: OpenAICredential
    ) async throws -> String
    func cancelActiveTranscription()
}

public extension OpenAITranscriptionServing {
    func cancelActiveTranscription() {}
}

protocol URLLoading: Sendable {
    func loadData(for request: URLRequest) async throws -> (Data, URLResponse)
}

protocol TranscriptionTimeoutSleeping: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

public struct OpenAITranscriptionService: OpenAITranscriptionServing, Sendable {
    static let defaultRequestTimeout: TimeInterval = 60

    private let requestBuilder: OpenAITranscriptionRequestBuilder
    private let urlUploader: any URLFileUploading
    private let timeoutSleeper: any TranscriptionTimeoutSleeping
    private let requestTimeout: TimeInterval
    private let decoder: JSONDecoder
    private let requestTaskCoordinator: OpenAIRequestTaskCoordinator

    public init() {
        self.init(
            requestBuilder: OpenAITranscriptionRequestBuilder(),
            urlUploader: OpenAIFileUploadTransport(),
            timeoutSleeper: TaskTranscriptionTimeoutSleeper(),
            requestTimeout: Self.defaultRequestTimeout,
            decoder: JSONDecoder(),
            requestTaskCoordinator: OpenAIRequestTaskCoordinator()
        )
    }

    init(
        requestBuilder: OpenAITranscriptionRequestBuilder,
        urlUploader: any URLFileUploading = OpenAIFileUploadTransport(),
        timeoutSleeper: any TranscriptionTimeoutSleeping = TaskTranscriptionTimeoutSleeper(),
        requestTimeout: TimeInterval = Self.defaultRequestTimeout,
        decoder: JSONDecoder = JSONDecoder(),
        requestTaskCoordinator: OpenAIRequestTaskCoordinator = OpenAIRequestTaskCoordinator()
    ) {
        self.requestBuilder = requestBuilder
        self.urlUploader = urlUploader
        self.timeoutSleeper = timeoutSleeper
        self.requestTimeout = requestTimeout > 0 ? requestTimeout : Self.defaultRequestTimeout
        self.decoder = decoder
        self.requestTaskCoordinator = requestTaskCoordinator
    }

    public func transcribe(
        _ request: AudioTranscriptionRequest,
        credential: OpenAICredential
    ) async throws -> String {
        let cleanupRegistration = requestBuilder.makeCleanupRegistration()
        defer { cleanupRegistration.requestCleanup() }

        let (data, response) = try await loadWithTimeout(
            request,
            cleanupRegistration: cleanupRegistration,
            credential: credential
        )
        try validateHTTPResponse(response)
        return try parseTranscript(from: data, promptComposition: request.promptComposition)
    }

    public func cancelActiveTranscription() {
        requestTaskCoordinator.cancelActiveRequest()
    }

    private func loadWithTimeout(
        _ transcriptionRequest: AudioTranscriptionRequest,
        cleanupRegistration: OpenAITranscriptionMultipartCleanupRegistration,
        credential: OpenAICredential
    ) async throws -> (Data, URLResponse) {
        do {
            return try await requestTaskCoordinator.perform {
                let preparation = try await requestBuilder.makePreparation(
                    transcriptionRequest,
                    cleanupRegistration: cleanupRegistration
                )
                defer { cleanupRegistration.requestCleanup() }
                let preparedUpload = try await preparation.prepareRequest()
                var request = preparedUpload.request
                request.timeoutInterval = requestTimeout
                request.setValue(
                    "Bearer \(credential.apiKey)",
                    forHTTPHeaderField: "Authorization"
                )
                try Task.checkCancellation()
                return try await urlUploader.uploadData(
                    for: request,
                    body: preparedUpload.body
                )
            } deadline: {
                try await timeoutSleeper.sleep(seconds: requestTimeout)
                throw OpenAITranscriptionServiceError.timedOut
            }
        } catch let error as OpenAITranscriptionServiceError {
            throw error
        } catch let error as OpenAITranscriptionRequestBuilderError {
            throw Self.mapRequestBuilderError(error)
        } catch let error as OpenAIFileUploadTransportError {
            throw Self.mapUploadTransportError(error)
        } catch let error as URLError {
            throw Self.mapURLError(error)
        } catch is CancellationError {
            throw OpenAITranscriptionServiceError.cancelled
        } catch {
            throw OpenAITranscriptionServiceError.networkFailure
        }
    }

    private static func mapRequestBuilderError(
        _ error: OpenAITranscriptionRequestBuilderError
    ) -> OpenAITranscriptionServiceError {
        switch error {
        case .multipartMetadataTooLarge:
            return .multipartMetadataTooLarge
        case .multipartBodyTooLarge, .multipartBodyUnavailable, .invalidMultipartBoundary:
            return .invalidRequest
        case .missingAudioFile,
             .emptyAudioFile,
             .unsupportedAudioFileType,
             .unreadableAudioFile,
             .audioFileChanged,
             .audioFileTooLarge,
             .invalidCustomLanguageCode:
            return .invalidRecording(error)
        }
    }

    private static func mapUploadTransportError(
        _ error: OpenAIFileUploadTransportError
    ) -> OpenAITranscriptionServiceError {
        switch error {
        case .invalidRequest:
            return .invalidRequest
        case .invalidResponse, .responseTooLarge, .redirectRejected:
            return .invalidResponse
        case .cancelled:
            return .cancelled
        case .transportFailure:
            return .networkFailure
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

    private func parseTranscript(
        from data: Data,
        promptComposition: TranscriptionPromptComposition
    ) throws -> String {
        do {
            let response = try decoder.decode(OpenAITranscriptionResponse.self, from: data)
            let transcript = try AcceptedTranscript(rawText: response.text).text
            guard !DictionaryEchoFilter.matches(
                transcript: transcript,
                dictionaryPrompt: promptComposition.dictionaryEchoGuardText
            ) else {
                throw OpenAITranscriptionServiceError.dictionaryEcho
            }

            guard !ActiveTextContextEchoFilter.matches(
                transcript: transcript,
                contextText: promptComposition.contextEchoGuardText
            ) else {
                throw OpenAITranscriptionServiceError.contextEcho
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

struct ActiveTextContextEchoFilter {
    static func matches(transcript: String?, contextText: String?) -> Bool {
        guard let transcript, let contextText else {
            return false
        }

        let transcriptWords = normalizedWords(in: transcript)
        let contextWords = normalizedWords(in: contextText)
        guard transcriptWords.count >= 4, contextWords.count >= transcriptWords.count else {
            return false
        }

        for startIndex in 0...(contextWords.count - transcriptWords.count) {
            let endIndex = startIndex + transcriptWords.count
            if Array(contextWords[startIndex..<endIndex]) == transcriptWords {
                return true
            }
        }

        return false
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

public nonisolated enum OpenAITranscriptionServiceError: Error, Equatable, LocalizedError, Sendable {
    case missingAPIKey
    case apiKeyUnavailable
    case invalidRecording(OpenAITranscriptionRequestBuilderError)
    case invalidRequest
    case multipartMetadataTooLarge
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
    case contextEcho

    public var errorDescription: String? {
        userFacingMessage
    }

    public var userFacingMessage: String {
        switch self {
        case .missingAPIKey:
            return "Enter an OpenAI API key before transcribing."
        case .apiKeyUnavailable:
            return "The OpenAI API key could not be read."
        case .invalidRecording(let error):
            return error.userFacingMessage
        case .invalidRequest:
            return "The transcription request could not be prepared."
        case .multipartMetadataTooLarge:
            return "The transcription request settings are too large."
        case .timedOut:
            return "Transcription timed out."
        case .networkUnavailable:
            return "The network is unavailable. Try again when you are connected."
        case .networkFailure:
            return "The transcription request failed. Try again."
        case .cancelled:
            return "Transcription was cancelled."
        case .invalidAPIKey:
            return "OpenAI rejected the saved API key."
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
        case .contextEcho:
            return "Only nearby context was detected."
        }
    }

    public var operatorLogCategory: String {
        switch self {
        case .missingAPIKey:
            return "missing_api_key"
        case .apiKeyUnavailable:
            return "api_key_unavailable"
        case .invalidRecording(let error):
            return error.operatorLogCategory
        case .invalidRequest:
            return "invalid_request"
        case .multipartMetadataTooLarge:
            return "multipart_metadata_too_large"
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
        case .contextEcho:
            return "context_echo"
        }
    }
}

nonisolated extension OpenAITranscriptionServiceError:
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    public var description: String {
        "OpenAITranscriptionServiceError(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [(label: String?, value: Any)](),
            displayStyle: .enum
        )
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
        case .audioFileChanged:
            return "The recording changed while the request was being prepared."
        case .audioFileTooLarge:
            return "The recording is too large to send."
        case .multipartMetadataTooLarge:
            return "The transcription request settings are too large."
        case .multipartBodyTooLarge, .multipartBodyUnavailable:
            return "The transcription request could not be prepared."
        case .invalidMultipartBoundary:
            return "The transcription request could not be prepared."
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
        case .audioFileChanged:
            return "changed_audio"
        case .audioFileTooLarge:
            return "audio_too_large"
        case .multipartMetadataTooLarge:
            return "multipart_metadata_too_large"
        case .multipartBodyTooLarge:
            return "multipart_body_too_large"
        case .multipartBodyUnavailable:
            return "multipart_body_unavailable"
        case .invalidMultipartBoundary:
            return "invalid_multipart_boundary"
        case .invalidCustomLanguageCode:
            return "invalid_language_code"
        }
    }
}

private struct OpenAITranscriptionResponse: Decodable {
    let text: String
}
