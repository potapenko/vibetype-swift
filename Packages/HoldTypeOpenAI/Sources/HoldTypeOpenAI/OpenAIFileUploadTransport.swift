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
        body: any OpenAIFileUploadBody
    ) async throws -> (Data, URLResponse)
}

/// A foreground-only, descriptor-backed upload transport with a bounded response.
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
        body: any OpenAIFileUploadBody
    ) async throws -> (Data, URLResponse) {
        let trustedRequest = try TrustedUploadRequest(request: request, body: body)
        let transfer = StreamedUploadTransfer(
            trustedRequest: trustedRequest,
            body: body,
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

nonisolated private struct TrustedUploadRequest: Sendable {
    let originalURL: URL
    let origin: UploadOrigin
    let timeoutInterval: TimeInterval
    let accept: String?
    let contentType: String
    let contentLength: String
    let authorization: String

    init(request: URLRequest, body: any OpenAIFileUploadBody) throws {
        guard let url = request.url,
              let origin = UploadOrigin(url: url),
              origin.scheme == "https",
              url.user == nil,
              url.password == nil,
              request.httpMethod?.uppercased() == "POST",
              request.httpBody == nil,
              request.httpBodyStream == nil,
              body.byteCount > 0,
              let contentType = request.value(forHTTPHeaderField: "Content-Type"),
              !contentType.isEmpty,
              let contentLength = request.value(forHTTPHeaderField: "Content-Length"),
              contentLength == String(body.byteCount),
              let authorization = request.value(forHTTPHeaderField: "Authorization"),
              Self.isTrustedBearerAuthorization(authorization),
              request.value(forHTTPHeaderField: "Transfer-Encoding") == nil else {
            throw OpenAIFileUploadTransportError.invalidRequest
        }

        originalURL = url
        self.origin = origin
        timeoutInterval = request.timeoutInterval
        accept = request.value(forHTTPHeaderField: "Accept")
        self.contentType = contentType
        self.contentLength = contentLength
        self.authorization = authorization
    }

    func makeRequest(url: URL) throws -> URLRequest {
        guard UploadOrigin(url: url) == origin,
              url.user == nil,
              url.password == nil else {
            throw OpenAIFileUploadTransportError.redirectRejected
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeoutInterval
        )
        request.httpMethod = "POST"
        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(contentLength, forHTTPHeaderField: "Content-Length")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.httpBody = nil
        request.httpBodyStream = nil
        return request
    }

    func permitsBody(for request: URLRequest?) -> Bool {
        guard let request,
              UploadOrigin(url: request.url) == origin,
              request.url?.user == nil,
              request.url?.password == nil,
              request.httpMethod?.uppercased() == "POST",
              request.value(forHTTPHeaderField: "Authorization") == authorization,
              request.value(forHTTPHeaderField: "Content-Type") == contentType,
              request.value(forHTTPHeaderField: "Content-Length") == contentLength,
              request.value(forHTTPHeaderField: "Accept") == accept else {
            return false
        }
        return true
    }

    private static func isTrustedBearerAuthorization(_ value: String) -> Bool {
        guard value.hasPrefix("Bearer "),
              value.count > "Bearer ".count,
              !value.contains("\r"),
              !value.contains("\n") else {
            return false
        }
        return value.dropFirst("Bearer ".count).allSatisfy { !$0.isWhitespace }
    }
}

nonisolated enum OpenAIUploadAuthenticationPolicy {
    enum Decision: Equatable, Sendable {
        case ignoreSupersededTask
        case performDefaultHandling
        case rejectActiveChallenge
    }

    static func decision(
        isActiveTask: Bool,
        authenticationMethod: String
    ) -> Decision {
        guard isActiveTask else {
            return .ignoreSupersededTask
        }
        return authenticationMethod == NSURLAuthenticationMethodServerTrust
            ? .performDefaultHandling
            : .rejectActiveChallenge
    }
}

nonisolated final class OpenAIUploadBodyGrantController: @unchecked Sendable {
    private enum GrantKind {
        case initial
        case approvedReplay
    }

    private struct Grant {
        let taskIdentifier: Int
        let kind: GrantKind
    }

    private let lock = NSLock()
    private var grant: Grant?
    private var didInstallInitialGrant = false
    private var didApproveReplay = false

    func installInitialGrant(forTaskIdentifier taskIdentifier: Int) -> Bool {
        lock.withLock {
            guard !didInstallInitialGrant, grant == nil else { return false }
            didInstallInitialGrant = true
            grant = Grant(taskIdentifier: taskIdentifier, kind: .initial)
            return true
        }
    }

    func consumeFullBodyGrant(forTaskIdentifier taskIdentifier: Int) -> Bool {
        lock.withLock {
            guard grant?.taskIdentifier == taskIdentifier else { return false }
            grant = nil
            return true
        }
    }

    func approveReplay(forTaskIdentifier taskIdentifier: Int) -> Bool {
        lock.withLock {
            guard grant == nil, !didApproveReplay else { return false }
            didApproveReplay = true
            grant = Grant(
                taskIdentifier: taskIdentifier,
                kind: .approvedReplay
            )
            return true
        }
    }

    func consumeOffsetReplayGrant(
        forTaskIdentifier taskIdentifier: Int,
        offset: Int64,
        byteCount: Int64
    ) -> Bool {
        lock.withLock {
            guard grant?.taskIdentifier == taskIdentifier,
                  grant?.kind == .approvedReplay else {
                return false
            }
            grant = nil
            return offset == 0 && byteCount > 0
        }
    }
}

nonisolated private final class StreamedUploadTransfer: NSObject, @unchecked Sendable {
    typealias Output = (Data, URLResponse)
    typealias ConfigurationFactory = @Sendable () -> URLSessionConfiguration

    private struct State {
        var continuation: CheckedContinuation<Output, Error>?
        var session: URLSession?
        var task: URLSessionUploadTask?
        var activeTaskIdentifier: Int?
        var supersededTaskIdentifiers: Set<Int> = []
        var redirectCount = 0
        var body: (any OpenAIFileUploadBody)?
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

    private let trustedRequest: TrustedUploadRequest
    private let maximumResponseByteCount: Int
    private let configurationFactory: ConfigurationFactory
    private let bodyGrantController = OpenAIUploadBodyGrantController()
    private let lock = NSLock()
    private var state = State()

    init(
        trustedRequest: TrustedUploadRequest,
        body: any OpenAIFileUploadBody,
        maximumResponseByteCount: Int,
        configurationFactory: @escaping ConfigurationFactory
    ) {
        self.trustedRequest = trustedRequest
        self.maximumResponseByteCount = maximumResponseByteCount
        self.configurationFactory = configurationFactory
        state.body = body
    }

    func start() async throws -> Output {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
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

            do {
                let request = try trustedRequest.makeRequest(url: trustedRequest.originalURL)
                let configuration = OpenAIFileUploadTransport.hardenedConfiguration(
                    configurationFactory()
                )
                let session = URLSession(
                    configuration: configuration,
                    delegate: self,
                    delegateQueue: nil
                )
                let task = session.uploadTask(withStreamedRequest: request)
                guard bodyGrantController.installInitialGrant(
                    forTaskIdentifier: task.taskIdentifier
                ) else {
                    task.cancel()
                    session.invalidateAndCancel()
                    throw OpenAIFileUploadTransportError.invalidRequest
                }

                let shouldStart = lock.withLock {
                    guard state.terminalResult == nil else {
                        return false
                    }
                    state.session = session
                    state.task = task
                    state.activeTaskIdentifier = task.taskIdentifier
                    return true
                }

                if shouldStart {
                    task.resume()
                } else {
                    task.cancel()
                    session.invalidateAndCancel()
                }
            } catch {
                finish(with: .failure(error), cancelTask: true)
            }
        }
    }

    func cancel() {
        finish(
            with: .failure(OpenAIFileUploadTransportError.cancelled),
            cancelTask: true
        )
    }

    private func finish(
        with result: Result<Output, Error>,
        cancelTask: Bool,
        requiredActiveTaskIdentifier: Int? = nil
    ) {
        let completion = lock.withLock { () -> Completion? in
            guard state.terminalResult == nil else {
                return nil
            }
            if let requiredActiveTaskIdentifier,
               state.activeTaskIdentifier != requiredActiveTaskIdentifier {
                return nil
            }

            state.terminalResult = result
            let completion = Completion(
                continuation: state.continuation,
                session: state.session,
                task: state.task,
                result: result,
                cancelTask: cancelTask
            )
            state.continuation = nil
            state.session = nil
            state.task = nil
            state.activeTaskIdentifier = nil
            state.supersededTaskIdentifiers.removeAll(keepingCapacity: false)
            state.body = nil
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

extension StreamedUploadTransfer: URLSessionDataDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        let isActiveTask = lock.withLock {
            state.terminalResult == nil
                && state.activeTaskIdentifier == task.taskIdentifier
        }
        switch OpenAIUploadAuthenticationPolicy.decision(
            isActiveTask: isActiveTask,
            authenticationMethod: challenge.protectionSpace.authenticationMethod
        ) {
        case .ignoreSupersededTask:
            completionHandler(.cancelAuthenticationChallenge, nil)
        case .performDefaultHandling:
            completionHandler(.performDefaultHandling, nil)
        case .rejectActiveChallenge:
            completionHandler(.cancelAuthenticationChallenge, nil)
            finish(
                with: .failure(OpenAIFileUploadTransportError.redirectRejected),
                cancelTask: true,
                requiredActiveTaskIdentifier: task.taskIdentifier
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        needNewBodyStream completionHandler: @escaping (InputStream?) -> Void
    ) {
        let isActiveTask = lock.withLock {
            state.terminalResult == nil
                && state.activeTaskIdentifier == task.taskIdentifier
        }
        guard isActiveTask else {
            completionHandler(nil)
            return
        }
        guard let body = lock.withLock({ state.body }) else {
            completionHandler(nil)
            return
        }
        guard trustedRequest.permitsBody(for: task.currentRequest),
              bodyGrantController.consumeFullBodyGrant(
                  forTaskIdentifier: task.taskIdentifier
              ) else {
            completionHandler(nil)
            let isStillActive = lock.withLock {
                state.terminalResult == nil
                    && state.activeTaskIdentifier == task.taskIdentifier
            }
            guard isStillActive else { return }
            finish(
                with: .failure(OpenAIFileUploadTransportError.redirectRejected),
                cancelTask: true,
                requiredActiveTaskIdentifier: task.taskIdentifier
            )
            return
        }

        do {
            let taskIdentifier = task.taskIdentifier
            let stream = try body.makeInputStream { [weak self] error in
                self?.finish(
                    with: .failure(error),
                    cancelTask: true,
                    requiredActiveTaskIdentifier: taskIdentifier
                )
            }
            let shouldProvide = lock.withLock {
                state.terminalResult == nil
                    && state.activeTaskIdentifier == task.taskIdentifier
            }
            if shouldProvide {
                completionHandler(stream)
            } else {
                stream.close()
                completionHandler(nil)
            }
        } catch {
            completionHandler(nil)
            finish(
                with: .failure(OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable),
                cancelTask: true,
                requiredActiveTaskIdentifier: task.taskIdentifier
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        needNewBodyStreamFrom offset: Int64,
        completionHandler: @escaping (InputStream?) -> Void
    ) {
        let isActiveTask = lock.withLock {
            state.terminalResult == nil
                && state.activeTaskIdentifier == task.taskIdentifier
        }
        guard isActiveTask else {
            completionHandler(nil)
            return
        }
        guard let body = lock.withLock({ state.body }) else {
            completionHandler(nil)
            return
        }
        guard trustedRequest.permitsBody(for: task.currentRequest),
              bodyGrantController.consumeOffsetReplayGrant(
                  forTaskIdentifier: task.taskIdentifier,
                  offset: offset,
                  byteCount: body.byteCount
              ) else {
            completionHandler(nil)
            let isStillActive = lock.withLock {
                state.terminalResult == nil
                    && state.activeTaskIdentifier == task.taskIdentifier
            }
            guard isStillActive else { return }
            finish(
                with: .failure(OpenAIFileUploadTransportError.redirectRejected),
                cancelTask: true,
                requiredActiveTaskIdentifier: task.taskIdentifier
            )
            return
        }

        do {
            let taskIdentifier = task.taskIdentifier
            let stream = try body.makeInputStream(
                startingAtOffset: offset
            ) { [weak self] error in
                self?.finish(
                    with: .failure(error),
                    cancelTask: true,
                    requiredActiveTaskIdentifier: taskIdentifier
                )
            }
            let shouldProvide = lock.withLock {
                state.terminalResult == nil
                    && state.activeTaskIdentifier == task.taskIdentifier
            }
            if shouldProvide {
                completionHandler(stream)
            } else {
                stream.close()
                completionHandler(nil)
            }
        } catch {
            completionHandler(nil)
            finish(
                with: .failure(OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable),
                cancelTask: true,
                requiredActiveTaskIdentifier: task.taskIdentifier
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let isActiveTask = lock.withLock {
            state.terminalResult == nil
                && state.activeTaskIdentifier == dataTask.taskIdentifier
        }
        guard isActiveTask else {
            completionHandler(.cancel)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(
                with: .failure(OpenAIFileUploadTransportError.invalidResponse),
                cancelTask: true,
                requiredActiveTaskIdentifier: dataTask.taskIdentifier
            )
            return
        }
        guard UploadOrigin(url: httpResponse.url) == trustedRequest.origin else {
            completionHandler(.cancel)
            finish(
                with: .failure(OpenAIFileUploadTransportError.redirectRejected),
                cancelTask: true,
                requiredActiveTaskIdentifier: dataTask.taskIdentifier
            )
            return
        }
        guard !isDeclaredResponseTooLarge(httpResponse) else {
            completionHandler(.cancel)
            finish(
                with: .failure(OpenAIFileUploadTransportError.responseTooLarge),
                cancelTask: true,
                requiredActiveTaskIdentifier: dataTask.taskIdentifier
            )
            return
        }

        let shouldAllow = lock.withLock {
            guard state.terminalResult == nil,
                  state.activeTaskIdentifier == dataTask.taskIdentifier else {
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
            guard state.terminalResult == nil,
                  state.activeTaskIdentifier == dataTask.taskIdentifier else {
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
                cancelTask: true,
                requiredActiveTaskIdentifier: dataTask.taskIdentifier
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
        let isActiveTask = lock.withLock {
            state.terminalResult == nil
                && state.activeTaskIdentifier == task.taskIdentifier
        }
        guard isActiveTask else {
            completionHandler(nil)
            return
        }
        guard response.statusCode == 307 || response.statusCode == 308,
              let destination = request.url,
              UploadOrigin(url: destination) == trustedRequest.origin else {
            completionHandler(nil)
            finish(
                with: .failure(OpenAIFileUploadTransportError.redirectRejected),
                cancelTask: true,
                requiredActiveTaskIdentifier: task.taskIdentifier
            )
            return
        }

        let reservedRedirect = lock.withLock { () -> Bool in
            guard state.terminalResult == nil,
                  state.activeTaskIdentifier == task.taskIdentifier,
                  state.redirectCount == 0 else {
                return false
            }
            state.redirectCount = 1
            return true
        }
        guard reservedRedirect else {
            completionHandler(nil)
            finish(
                with: .failure(OpenAIFileUploadTransportError.redirectRejected),
                cancelTask: true,
                requiredActiveTaskIdentifier: task.taskIdentifier
            )
            return
        }

        let replayRequest: URLRequest
        do {
            replayRequest = try trustedRequest.makeRequest(url: destination)
        } catch {
            completionHandler(nil)
            finish(
                with: .failure(OpenAIFileUploadTransportError.redirectRejected),
                cancelTask: true,
                requiredActiveTaskIdentifier: task.taskIdentifier
            )
            return
        }

        let replayTask = session.uploadTask(withStreamedRequest: replayRequest)
        guard bodyGrantController.approveReplay(
            forTaskIdentifier: replayTask.taskIdentifier
        ) else {
            replayTask.cancel()
            completionHandler(nil)
            finish(
                with: .failure(OpenAIFileUploadTransportError.redirectRejected),
                cancelTask: true,
                requiredActiveTaskIdentifier: task.taskIdentifier
            )
            return
        }
        let shouldStartReplay = lock.withLock { () -> Bool in
            guard state.terminalResult == nil,
                  state.activeTaskIdentifier == task.taskIdentifier else {
                return false
            }
            state.supersededTaskIdentifiers.insert(task.taskIdentifier)
            state.task = replayTask
            state.activeTaskIdentifier = replayTask.taskIdentifier
            state.response = nil
            state.responseData.removeAll(keepingCapacity: false)
            return true
        }
        completionHandler(nil)
        if shouldStartReplay {
            replayTask.resume()
        } else {
            replayTask.cancel()
            finish(
                with: .failure(OpenAIFileUploadTransportError.redirectRejected),
                cancelTask: true,
                requiredActiveTaskIdentifier: task.taskIdentifier
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let shouldIgnore = lock.withLock { () -> Bool in
            if state.supersededTaskIdentifiers.remove(task.taskIdentifier) != nil {
                return true
            }
            return state.activeTaskIdentifier != task.taskIdentifier
        }
        if shouldIgnore {
            return
        }

        if let error {
            if let localError = error as? OpenAITranscriptionRequestBuilderError {
                finish(
                    with: .failure(localError),
                    cancelTask: false,
                    requiredActiveTaskIdentifier: task.taskIdentifier
                )
            } else if let urlError = error as? URLError {
                finish(
                    with: .failure(urlError),
                    cancelTask: false,
                    requiredActiveTaskIdentifier: task.taskIdentifier
                )
            } else {
                finish(
                    with: .failure(OpenAIFileUploadTransportError.transportFailure),
                    cancelTask: false,
                    requiredActiveTaskIdentifier: task.taskIdentifier
                )
            }
            return
        }

        let output = lock.withLock { () -> Output? in
            guard state.terminalResult == nil,
                  state.activeTaskIdentifier == task.taskIdentifier,
                  let response = state.response,
                  UploadOrigin(url: response.url) == trustedRequest.origin else {
                return nil
            }
            return (state.responseData, response)
        }

        guard let output else {
            finish(
                with: .failure(OpenAIFileUploadTransportError.invalidResponse),
                cancelTask: false,
                requiredActiveTaskIdentifier: task.taskIdentifier
            )
            return
        }
        finish(
            with: .success(output),
            cancelTask: false,
            requiredActiveTaskIdentifier: task.taskIdentifier
        )
    }
}
