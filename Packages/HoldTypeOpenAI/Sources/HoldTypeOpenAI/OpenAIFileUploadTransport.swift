//
//  OpenAIFileUploadTransport.swift
//  HoldType
//
//  Created by Codex on 7/10/26.
//

import Foundation

nonisolated protocol URLFileUploading: Sendable {
    func uploadData(
        for request: URLRequest,
        fromFile bodyFileURL: URL
    ) async throws -> (Data, URLResponse)
}

/// A foreground-only, file-backed upload transport with a bounded in-memory response.
nonisolated struct OpenAIFileUploadTransport: URLFileUploading, Sendable {
    static let maximumResponseByteCount = 1_048_576

    private let configurationFactory: @Sendable () -> URLSessionConfiguration

    init() {
        configurationFactory = { URLSessionConfiguration.ephemeral }
    }

    init(
        configurationFactory: @escaping @Sendable () -> URLSessionConfiguration
    ) {
        self.configurationFactory = configurationFactory
    }

    static func hardenedConfiguration(
        _ configuration: URLSessionConfiguration
    ) -> URLSessionConfiguration {
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        return configuration
    }

    func uploadData(
        for request: URLRequest,
        fromFile bodyFileURL: URL
    ) async throws -> (Data, URLResponse) {
        guard let origin = UploadOrigin(url: request.url) else {
            throw OpenAIFileUploadTransportError.invalidRequest
        }

        let transfer = FileUploadTransfer(
            request: request,
            bodyFileURL: bodyFileURL,
            origin: origin,
            maximumResponseByteCount: Self.maximumResponseByteCount,
            configurationFactory: configurationFactory
        )

        return try await withTaskCancellationHandler {
            try await transfer.start()
        } onCancel: {
            transfer.cancel()
        }
    }
}

nonisolated enum OpenAIFileUploadTransportError: Error, Equatable, LocalizedError, Sendable {
    case invalidRequest
    case invalidResponse
    case responseTooLarge
    case redirectRejected
    case cancelled
    case transportFailure

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The upload request is invalid."
        case .invalidResponse:
            return "The upload response is unreadable."
        case .responseTooLarge:
            return "The upload response exceeded the allowed size."
        case .redirectRejected:
            return "The upload redirect was rejected."
        case .cancelled:
            return "The upload was cancelled."
        case .transportFailure:
            return "The upload failed."
        }
    }

    var operatorLogCategory: String {
        switch self {
        case .invalidRequest:
            return "invalid_request"
        case .invalidResponse:
            return "invalid_response"
        case .responseTooLarge:
            return "response_too_large"
        case .redirectRejected:
            return "redirect_rejected"
        case .cancelled:
            return "cancelled"
        case .transportFailure:
            return "transport_failure"
        }
    }
}

nonisolated private struct UploadOrigin: Equatable, Sendable {
    let scheme: String
    let host: String
    let port: Int

    init?(url: URL?) {
        guard
            let url,
            let rawScheme = url.scheme?.lowercased(),
            let rawHost = url.host?.lowercased()
        else {
            return nil
        }

        let defaultPort: Int
        switch rawScheme {
        case "http":
            defaultPort = 80
        case "https":
            defaultPort = 443
        default:
            return nil
        }

        scheme = rawScheme
        host = rawHost
        port = url.port ?? defaultPort
    }
}

nonisolated private final class FileUploadTransfer: NSObject, @unchecked Sendable {
    typealias Output = (Data, URLResponse)
    typealias ConfigurationFactory = @Sendable () -> URLSessionConfiguration

    private struct State {
        var continuation: CheckedContinuation<Output, Error>?
        var session: URLSession?
        var task: URLSessionUploadTask?
        var response: HTTPURLResponse?
        var responseData = Data()
        var terminalResult: Result<Output, Error>?
    }

    private struct Completion {
        let continuation: CheckedContinuation<Output, Error>?
        let session: URLSession?
        let task: URLSessionUploadTask?
        let result: Result<Output, Error>
        let cancelTask: Bool
    }

    private let request: URLRequest
    private let bodyFileURL: URL
    private let origin: UploadOrigin
    private let maximumResponseByteCount: Int
    private let configurationFactory: ConfigurationFactory
    private let lock = NSLock()
    private var state = State()

    init(
        request: URLRequest,
        bodyFileURL: URL,
        origin: UploadOrigin,
        maximumResponseByteCount: Int,
        configurationFactory: @escaping ConfigurationFactory
    ) {
        self.request = request
        self.bodyFileURL = bodyFileURL
        self.origin = origin
        self.maximumResponseByteCount = maximumResponseByteCount
        self.configurationFactory = configurationFactory
    }

    func start() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            let terminalResult = lock.withLock { () -> Result<Output, Error>? in
                if let terminalResult = state.terminalResult {
                    return terminalResult
                }

                state.continuation = continuation
                return nil
            }

            if let terminalResult {
                resume(continuation, with: terminalResult)
                return
            }

            let configuration = makeConfiguration()
            let session = URLSession(
                configuration: configuration,
                delegate: self,
                delegateQueue: nil
            )
            let task = session.uploadTask(with: request, fromFile: bodyFileURL)

            let shouldStart = lock.withLock {
                guard state.terminalResult == nil else {
                    return false
                }

                state.session = session
                state.task = task
                return true
            }

            if shouldStart {
                task.resume()
            } else {
                task.cancel()
                session.invalidateAndCancel()
            }
        }
    }

    func cancel() {
        finish(
            with: .failure(OpenAIFileUploadTransportError.cancelled),
            cancelTask: true
        )
    }

    private func makeConfiguration() -> URLSessionConfiguration {
        OpenAIFileUploadTransport.hardenedConfiguration(configurationFactory())
    }

    private func finish(
        with result: Result<Output, Error>,
        cancelTask: Bool
    ) {
        let completion = lock.withLock { () -> Completion? in
            guard state.terminalResult == nil else {
                return nil
            }

            state.terminalResult = result
            let continuation = state.continuation
            state.continuation = nil
            let completion = Completion(
                continuation: continuation,
                session: state.session,
                task: state.task,
                result: result,
                cancelTask: cancelTask
            )
            state.session = nil
            state.task = nil
            state.response = nil
            state.responseData.removeAll(keepingCapacity: false)
            return completion
        }

        guard let completion else {
            return
        }

        if completion.cancelTask {
            completion.task?.cancel()
            completion.session?.invalidateAndCancel()
        } else {
            completion.session?.finishTasksAndInvalidate()
        }

        if let continuation = completion.continuation {
            resume(continuation, with: completion.result)
        }
    }

    private func resume(
        _ continuation: CheckedContinuation<Output, Error>,
        with result: Result<Output, Error>
    ) {
        switch result {
        case .success(let output):
            continuation.resume(returning: output)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func isDeclaredResponseTooLarge(_ response: HTTPURLResponse) -> Bool {
        if response.expectedContentLength > Int64(maximumResponseByteCount) {
            return true
        }

        guard let value = response.value(forHTTPHeaderField: "Content-Length") else {
            return false
        }

        return decimalByteCount(value, exceeds: maximumResponseByteCount)
    }

    private func decimalByteCount(_ rawValue: String, exceeds limit: Int) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return false
        }

        var byteCount = 0
        for character in value.utf8 {
            guard character >= 48, character <= 57 else {
                return false
            }

            let digit = Int(character - 48)
            if byteCount > (limit - digit) / 10 {
                return true
            }
            byteCount = (byteCount * 10) + digit
        }

        return byteCount > limit
    }
}

extension FileUploadTransfer: URLSessionDataDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(
                with: .failure(OpenAIFileUploadTransportError.invalidResponse),
                cancelTask: true
            )
            return
        }

        guard UploadOrigin(url: httpResponse.url) == origin else {
            completionHandler(.cancel)
            finish(
                with: .failure(OpenAIFileUploadTransportError.redirectRejected),
                cancelTask: true
            )
            return
        }

        guard !isDeclaredResponseTooLarge(httpResponse) else {
            completionHandler(.cancel)
            finish(
                with: .failure(OpenAIFileUploadTransportError.responseTooLarge),
                cancelTask: true
            )
            return
        }

        let shouldAllow = lock.withLock {
            guard state.terminalResult == nil else {
                return false
            }
            state.response = httpResponse
            return true
        }
        completionHandler(shouldAllow ? .allow : .cancel)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let exceededLimit = lock.withLock {
            guard state.terminalResult == nil else {
                return false
            }

            guard data.count <= maximumResponseByteCount - state.responseData.count else {
                return true
            }

            state.responseData.append(data)
            return false
        }

        if exceededLimit {
            finish(
                with: .failure(OpenAIFileUploadTransportError.responseTooLarge),
                cancelTask: true
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard UploadOrigin(url: request.url) == origin else {
            completionHandler(nil)
            finish(
                with: .failure(OpenAIFileUploadTransportError.redirectRejected),
                cancelTask: true
            )
            return
        }

        completionHandler(request)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            if let urlError = error as? URLError {
                finish(with: .failure(urlError), cancelTask: false)
            } else {
                finish(
                    with: .failure(OpenAIFileUploadTransportError.transportFailure),
                    cancelTask: false
                )
            }
            return
        }

        let output = lock.withLock { () -> Output? in
            guard
                state.terminalResult == nil,
                let response = state.response,
                UploadOrigin(url: response.url) == origin
            else {
                return nil
            }
            return (state.responseData, response)
        }

        guard let output else {
            finish(
                with: .failure(OpenAIFileUploadTransportError.invalidResponse),
                cancelTask: false
            )
            return
        }
        finish(with: .success(output), cancelTask: false)
    }
}
