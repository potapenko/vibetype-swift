//
//  OpenAIFileUploadTransportTests.swift
//  HoldTypeTests
//
//  Created by Codex on 7/10/26.
//

import Foundation
import Testing
@testable import HoldTypeOpenAI

@Suite(.serialized)
struct OpenAIFileUploadTransportTests {
    @Test func chunkedResponseBelowLimitIsAccumulatedInOrder() async throws {
        let chunks = [Data("one".utf8), Data("-two".utf8), Data("-three".utf8)]
        UploadTestURLProtocol.reset(actions: [
            "/upload": .response(statusCode: 200, headers: [:], chunks: chunks),
        ])

        let result = try await upload(to: "https://upload.example/upload")

        #expect(result.0 == Data("one-two-three".utf8))
        #expect((result.1 as? HTTPURLResponse)?.statusCode == 200)
        #expect(UploadTestURLProtocol.observations.count == 1)
    }

    @Test func hardeningDisablesSharedSessionStoresWithoutRemovingProtocolSeam() {
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [UploadTestURLProtocol.self]

        let hardened = OpenAIFileUploadTransport.hardenedConfiguration(configuration)

        #expect(hardened.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(hardened.urlCache == nil)
        #expect(hardened.httpCookieStorage == nil)
        #expect(hardened.httpShouldSetCookies == false)
        #expect(hardened.urlCredentialStorage == nil)
        #expect(hardened.waitsForConnectivity == false)
        #expect(hardened.protocolClasses?.contains { $0 == UploadTestURLProtocol.self } == true)
    }

    @Test func fileUploadDoesNotMutateCallerRequestIntoAnInMemoryBody() async throws {
        UploadTestURLProtocol.reset(actions: [
            "/upload": .response(statusCode: 200, headers: [:], chunks: [Data("ok".utf8)]),
        ])
        let bodyFileURL = try makeBodyFile()
        defer { try? FileManager.default.removeItem(at: bodyFileURL.deletingLastPathComponent()) }
        var request = URLRequest(url: URL(string: "https://upload.example/upload")!)
        request.httpMethod = "POST"
        request.setValue("Bearer private-test-key", forHTTPHeaderField: "Authorization")

        #expect(request.httpBody == nil)
        #expect(request.httpBodyStream == nil)
        _ = try await makeTransport().uploadData(for: request, fromFile: bodyFileURL)
        #expect(request.httpBody == nil)
        #expect(request.httpBodyStream == nil)
    }

    @Test func responseAtExactLimitIsAccepted() async throws {
        let maximum = OpenAIFileUploadTransport.maximumResponseByteCount
        let responseData = Data(repeating: 0x61, count: maximum)
        UploadTestURLProtocol.reset(actions: [
            "/upload": .response(
                statusCode: 200,
                headers: ["Content-Length": String(maximum)],
                chunks: [responseData]
            ),
        ])

        let result = try await upload(to: "https://upload.example/upload")

        #expect(result.0.count == maximum)
        #expect(result.0 == responseData)
    }

    @Test func responseOneByteOverLimitIsRejectedBeforeItIsReturned() async throws {
        let maximum = OpenAIFileUploadTransport.maximumResponseByteCount
        UploadTestURLProtocol.reset(actions: [
            "/upload": .response(
                statusCode: 200,
                headers: [:],
                chunks: [Data(repeating: 0x61, count: maximum), Data([0x62])]
            ),
        ])

        await expectTransportError(.responseTooLarge) {
            try await upload(to: "https://upload.example/upload")
        }
    }

    @Test func oversizedDeclaredContentLengthIsRejected() async throws {
        let declaredLength = OpenAIFileUploadTransport.maximumResponseByteCount + 1
        UploadTestURLProtocol.reset(actions: [
            "/upload": .response(
                statusCode: 200,
                headers: ["Content-Length": String(declaredLength)],
                chunks: [Data("must not be accepted".utf8)]
            ),
        ])

        await expectTransportError(.responseTooLarge) {
            try await upload(to: "https://upload.example/upload")
        }
    }

    @Test func sameOriginRedirectAllowsEquivalentExplicitDefaultPort() async throws {
        UploadTestURLProtocol.reset(actions: [
            "/start": .redirect(to: URL(string: "https://upload.example:443/final")!),
            "/final": .response(
                statusCode: 200,
                headers: [:],
                chunks: [Data("redirected".utf8)]
            ),
        ])

        let result = try await upload(to: "https://upload.example/start")

        #expect(result.0 == Data("redirected".utf8))
        #expect(UploadTestURLProtocol.observations.map(\.url.path) == ["/start", "/final"])
    }

    @Test func crossOriginRedirectsAreRejectedBeforeHeadersOrBodyReachDestination() async throws {
        let destinations = [
            "https://other.example/final",
            "http://upload.example/final",
            "https://upload.example:444/final",
        ]

        for destination in destinations {
            UploadTestURLProtocol.reset(actions: [
                "/start": .redirect(to: URL(string: destination)!),
                "/final": .response(statusCode: 200, headers: [:], chunks: [Data("unsafe".utf8)]),
            ])

            await expectTransportError(.redirectRejected) {
                try await upload(to: "https://upload.example/start")
            }

            let observations = UploadTestURLProtocol.observations
            #expect(observations.count == 1)
            #expect(observations.first?.url.path == "/start")
            #expect(observations.first?.authorization == "Bearer private-test-key")
            #expect(observations.contains { $0.url.absoluteString == destination } == false)
        }
    }

    @Test func parentTaskCancellationCancelsTransportAndCompletesPromptly() async throws {
        UploadTestURLProtocol.reset(actions: ["/upload": .waitForCancellation])
        let probe = UploadResultProbe()
        let task = Task {
            do {
                probe.complete(.success(try await upload(to: "https://upload.example/upload")))
            } catch {
                probe.complete(.failure(error))
            }
        }
        try await waitUntil { UploadTestURLProtocol.observations.count == 1 }

        task.cancel()

        let result = try await probe.waitForResult()
        await task.value
        assertTransportError(.cancelled, in: result)
        try await waitUntil { UploadTestURLProtocol.waitingStopCount == 1 }
    }

    @Test func cancellationAndCompletionRaceStillCompletesExactlyOnce() async throws {
        for _ in 0..<20 {
            UploadTestURLProtocol.reset(actions: ["/upload": .waitForCancellation])
            let probe = UploadResultProbe()
            let task = Task {
                do {
                    probe.complete(.success(try await upload(to: "https://upload.example/upload")))
                } catch {
                    probe.complete(.failure(error))
                }
            }
            try await waitUntil { UploadTestURLProtocol.observations.count == 1 }

            let finisher = Task.detached {
                UploadTestURLProtocol.completeWaitingRequest(
                    statusCode: 200,
                    chunks: [Data("race".utf8)]
                )
            }
            task.cancel()

            let result = try await probe.waitForResult()
            await finisher.value
            await task.value
            #expect(probe.completionCount == 1)
            switch result {
            case .success(let output):
                #expect(output.0 == Data("race".utf8))
            case .failure(let error):
                #expect(error as? OpenAIFileUploadTransportError == .cancelled)
            }
        }
    }

    @Test func nonHTTPResponseIsRejectedAsInvalid() async throws {
        UploadTestURLProtocol.reset(actions: [
            "/upload": .nonHTTPResponse(chunks: [Data("not http".utf8)]),
        ])

        await expectTransportError(.invalidResponse) {
            try await upload(to: "https://upload.example/upload")
        }
    }

    @Test func URLSessionTransportErrorPreservesURLErrorCode() async throws {
        UploadTestURLProtocol.reset(actions: [
            "/upload": .failure(URLError(.notConnectedToInternet)),
        ])

        do {
            _ = try await upload(to: "https://upload.example/upload")
            Issue.record("Expected the URL loading error to be preserved.")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        } catch {
            Issue.record("Expected URLError.notConnectedToInternet, got \(error)")
        }
    }

    @Test func invalidRequestAndTypedErrorsExposeOnlyRedactedValues() async throws {
        let secretValues = [
            "private-test-key",
            "sensitive-request-body",
            "upload.example/private-path",
        ]
        let errors: [OpenAIFileUploadTransportError] = [
            .invalidRequest,
            .invalidResponse,
            .responseTooLarge,
            .redirectRejected,
            .cancelled,
            .transportFailure,
        ]

        for error in errors {
            let rendered = [
                String(describing: error),
                String(reflecting: error),
                error.localizedDescription,
                error.operatorLogCategory,
            ].joined(separator: " ")
            for secret in secretValues {
                #expect(rendered.contains(secret) == false)
            }
        }

        var invalidRequest = URLRequest(url: URL(string: "file:///private-path")!)
        invalidRequest.httpMethod = "POST"
        invalidRequest.setValue("Bearer private-test-key", forHTTPHeaderField: "Authorization")
        let bodyFileURL = try makeBodyFile()
        defer { try? FileManager.default.removeItem(at: bodyFileURL.deletingLastPathComponent()) }

        await expectTransportError(.invalidRequest) {
            try await makeTransport().uploadData(for: invalidRequest, fromFile: bodyFileURL)
        }
        requireSendable(makeTransport())
        requireSendable(OpenAIFileUploadTransportError.cancelled)
    }

    private func upload(to urlString: String) async throws -> (Data, URLResponse) {
        let bodyFileURL = try makeBodyFile()
        defer { try? FileManager.default.removeItem(at: bodyFileURL.deletingLastPathComponent()) }

        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("Bearer private-test-key", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=test", forHTTPHeaderField: "Content-Type")
        return try await makeTransport().uploadData(for: request, fromFile: bodyFileURL)
    }

    private func makeTransport() -> OpenAIFileUploadTransport {
        OpenAIFileUploadTransport {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [UploadTestURLProtocol.self]
            return configuration
        }
    }

    private func makeBodyFile() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("holdtype-upload-transport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let bodyFileURL = directoryURL.appendingPathComponent("request-body")
        try Data("sensitive-request-body".utf8).write(to: bodyFileURL)
        return bodyFileURL
    }
}

private func expectTransportError(
    _ expectedError: OpenAIFileUploadTransportError,
    operation: () async throws -> (Data, URLResponse)
) async {
    do {
        _ = try await operation()
        Issue.record("Expected OpenAIFileUploadTransportError.\(expectedError)")
    } catch let error as OpenAIFileUploadTransportError {
        #expect(error == expectedError)
    } catch {
        Issue.record("Expected OpenAIFileUploadTransportError, got \(error)")
    }
}

private func assertTransportError(
    _ expectedError: OpenAIFileUploadTransportError,
    in result: Result<(Data, URLResponse), Error>
) {
    switch result {
    case .success:
        Issue.record("Expected OpenAIFileUploadTransportError.\(expectedError)")
    case .failure(let error):
        #expect(error as? OpenAIFileUploadTransportError == expectedError)
    }
}

private func requireSendable<T: Sendable>(_ value: T) {}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @Sendable () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
    while !condition() {
        guard clock.now < deadline else {
            throw UploadTestTimeout()
        }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
}

private struct UploadTestTimeout: Error {}

private final class UploadResultProbe: @unchecked Sendable {
    typealias Output = Result<(Data, URLResponse), Error>

    private let lock = NSLock()
    private var storedResult: Output?
    private var storedCompletionCount = 0

    var completionCount: Int {
        lock.withLock { storedCompletionCount }
    }

    func complete(_ result: Output) {
        lock.withLock {
            storedCompletionCount += 1
            if storedResult == nil {
                storedResult = result
            }
        }
    }

    func waitForResult() async throws -> Output {
        try await waitUntil { [self] in
            lock.withLock { storedResult != nil }
        }
        return try lock.withLock {
            guard let storedResult else {
                throw UploadTestTimeout()
            }
            return storedResult
        }
    }
}

private final class UploadTestURLProtocol: URLProtocol {
    enum Action: @unchecked Sendable {
        case response(statusCode: Int, headers: [String: String], chunks: [Data])
        case redirect(to: URL)
        case waitForCancellation
        case nonHTTPResponse(chunks: [Data])
        case failure(Error)
    }

    struct Observation: Sendable {
        let url: URL
        let authorization: String?
        let hasBodyOrStream: Bool
    }

    private static let controller = Controller()

    static var observations: [Observation] {
        controller.observations
    }

    static var waitingStopCount: Int {
        controller.waitingStopCount
    }

    static func reset(actions: [String: Action]) {
        controller.reset(actions: actions)
    }

    static func completeWaitingRequest(statusCode: Int, chunks: [Data]) {
        controller.completeWaitingRequest(statusCode: statusCode, chunks: chunks)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let action = Self.controller.start(protocol: self, request: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        switch action {
        case let .response(statusCode, headers, chunks):
            sendHTTPResponse(statusCode: statusCode, headers: headers, chunks: chunks)
        case .redirect(let destination):
            sendRedirect(to: destination)
        case .waitForCancellation:
            return
        case .nonHTTPResponse(let chunks):
            let response = URLResponse(
                url: request.url!,
                mimeType: "application/json",
                expectedContentLength: -1,
                textEncodingName: nil
            )
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        Self.controller.stop(protocol: self)
    }

    fileprivate func sendHTTPResponse(
        statusCode: Int,
        headers: [String: String] = [:],
        chunks: [Data]
    ) {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    private func sendRedirect(to destination: URL) {
        guard let sourceURL = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: sourceURL,
            statusCode: 307,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": destination.absoluteString]
        )!
        var redirectedRequest = request
        redirectedRequest.url = destination
        client?.urlProtocol(self, wasRedirectedTo: redirectedRequest, redirectResponse: response)
    }

    private final class Controller: @unchecked Sendable {
        private let lock = NSLock()
        private var actions: [String: Action] = [:]
        private var storedObservations: [Observation] = []
        private var waitingProtocols: [ObjectIdentifier: UploadTestURLProtocol] = [:]
        private var storedWaitingStopCount = 0

        var observations: [Observation] {
            lock.withLock { storedObservations }
        }

        var waitingStopCount: Int {
            lock.withLock { storedWaitingStopCount }
        }

        func reset(actions: [String: Action]) {
            lock.withLock {
                self.actions = actions
                storedObservations = []
                waitingProtocols = [:]
                storedWaitingStopCount = 0
            }
        }

        func start(protocol urlProtocol: UploadTestURLProtocol, request: URLRequest) -> Action? {
            lock.withLock {
                guard let url = request.url else {
                    return nil
                }
                storedObservations.append(
                    Observation(
                        url: url,
                        authorization: request.value(forHTTPHeaderField: "Authorization"),
                        hasBodyOrStream: request.httpBody != nil || request.httpBodyStream != nil
                    )
                )
                let action = actions[url.path]
                if case .waitForCancellation = action {
                    waitingProtocols[ObjectIdentifier(urlProtocol)] = urlProtocol
                }
                return action
            }
        }

        func stop(protocol urlProtocol: UploadTestURLProtocol) {
            lock.withLock {
                if waitingProtocols.removeValue(forKey: ObjectIdentifier(urlProtocol)) != nil {
                    storedWaitingStopCount += 1
                }
            }
        }

        func completeWaitingRequest(statusCode: Int, chunks: [Data]) {
            let protocols = lock.withLock { () -> [UploadTestURLProtocol] in
                let protocols = Array(waitingProtocols.values)
                waitingProtocols = [:]
                return protocols
            }
            for urlProtocol in protocols {
                urlProtocol.sendHTTPResponse(statusCode: statusCode, chunks: chunks)
            }
        }
    }
}
