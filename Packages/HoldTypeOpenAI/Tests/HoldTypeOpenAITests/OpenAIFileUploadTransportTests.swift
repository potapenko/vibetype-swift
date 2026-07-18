//
//  OpenAIFileUploadTransportTests.swift
//  HoldTypeTests
//
//  Created by Codex on 7/10/26.
//

import Darwin
import Foundation
import HoldTypeDomain
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
        let body = TestUploadBody(data: Data("sensitive-request-body".utf8))
        var request = URLRequest(url: URL(string: "https://upload.example/upload")!)
        request.httpMethod = "POST"
        request.setValue("Bearer private-test-key", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=test", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.byteCount), forHTTPHeaderField: "Content-Length")

        #expect(request.httpBody == nil)
        #expect(request.httpBodyStream == nil)
        _ = try await makeTransport().uploadData(for: request, body: body)
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

    @Test func sameOrigin307And308ReplayBearerAndByteIdenticalBody() async throws {
        for statusCode in [307, 308] {
            UploadTestURLProtocol.reset(actions: [
                "/start": .redirect(
                    statusCode: statusCode,
                    to: URL(string: "https://upload.example:443/final")!
                ),
                "/final": .response(
                    statusCode: 200,
                    headers: [:],
                    chunks: [Data("redirected".utf8)]
                ),
            ])

            let result = try await upload(to: "https://upload.example/start")
            let observations = UploadTestURLProtocol.observations

            #expect(result.0 == Data("redirected".utf8))
            #expect(observations.map(\.url.path) == ["/start", "/final"])
            #expect(observations.map(\.authorization) == [
                "Bearer private-test-key",
                "Bearer private-test-key",
            ])
            #expect(observations[0].body == Data("sensitive-request-body".utf8))
            #expect(observations[1].body == observations[0].body)
        }
    }

    @Test func redirect301302And303AreRejectedBeforeDestinationDelivery() async throws {
        for statusCode in [301, 302, 303] {
            UploadTestURLProtocol.reset(actions: [
                "/start": .redirect(
                    statusCode: statusCode,
                    to: URL(string: "https://upload.example/final")!
                ),
                "/final": .response(statusCode: 200, headers: [:], chunks: [Data("unsafe".utf8)]),
            ])

            await expectTransportError(.redirectRejected) {
                try await upload(to: "https://upload.example/start")
            }

            let observations = UploadTestURLProtocol.observations
            #expect(observations.map(\.url.path) == ["/start"])
            #expect(observations.first?.authorization == "Bearer private-test-key")
            #expect(observations.contains { $0.url.path == "/final" } == false)
        }
    }

    @Test func secondSameOriginRedirectIsRejectedBeforeThirdDelivery() async throws {
        UploadTestURLProtocol.reset(actions: [
            "/start": .redirect(
                statusCode: 307,
                to: URL(string: "https://upload.example/second")!
            ),
            "/second": .redirect(
                statusCode: 308,
                to: URL(string: "https://upload.example/third")!
            ),
            "/third": .response(statusCode: 200, headers: [:], chunks: [Data("unsafe".utf8)]),
        ])

        await expectTransportError(.redirectRejected) {
            try await upload(to: "https://upload.example/start")
        }

        let observations = UploadTestURLProtocol.observations
        #expect(observations.map(\.url.path) == ["/start", "/second"])
        #expect(observations.allSatisfy { $0.authorization == "Bearer private-test-key" })
        #expect(observations.allSatisfy { $0.body == Data("sensitive-request-body".utf8) })
        #expect(observations.contains { $0.url.path == "/third" } == false)
    }

    @Test func bodyGrantRejectsAuthStyleExtraAndNonzeroOffsetReplays() {
        let grants = OpenAIUploadBodyGrantController()
        #expect(grants.installInitialGrant(forTaskIdentifier: 1))
        #expect(grants.consumeFullBodyGrant(forTaskIdentifier: 1))
        #expect(grants.consumeFullBodyGrant(forTaskIdentifier: 1) == false)

        #expect(grants.approveReplay(forTaskIdentifier: 2))
        #expect(grants.consumeFullBodyGrant(forTaskIdentifier: 1) == false)
        #expect(
            grants.consumeOffsetReplayGrant(
                forTaskIdentifier: 2,
                offset: 0,
                byteCount: 20
            )
        )
        #expect(grants.consumeFullBodyGrant(forTaskIdentifier: 2) == false)
        #expect(grants.approveReplay(forTaskIdentifier: 3) == false)

        let nonzeroOffset = OpenAIUploadBodyGrantController()
        #expect(nonzeroOffset.installInitialGrant(forTaskIdentifier: 10))
        #expect(nonzeroOffset.consumeFullBodyGrant(forTaskIdentifier: 10))
        #expect(nonzeroOffset.approveReplay(forTaskIdentifier: 11))
        #expect(
            nonzeroOffset.consumeOffsetReplayGrant(
                forTaskIdentifier: 11,
                offset: 1,
                byteCount: 20
            ) == false
        )
        #expect(nonzeroOffset.consumeFullBodyGrant(forTaskIdentifier: 11) == false)

        let negativeOffset = OpenAIUploadBodyGrantController()
        #expect(negativeOffset.installInitialGrant(forTaskIdentifier: 20))
        #expect(negativeOffset.consumeFullBodyGrant(forTaskIdentifier: 20))
        #expect(negativeOffset.approveReplay(forTaskIdentifier: 21))
        #expect(
            negativeOffset.consumeOffsetReplayGrant(
                forTaskIdentifier: 21,
                offset: -1,
                byteCount: 20
            ) == false
        )
        #expect(negativeOffset.consumeFullBodyGrant(forTaskIdentifier: 21) == false)
        #expect(
            OpenAIUploadAuthenticationPolicy.decision(
                isActiveTask: true,
                authenticationMethod: NSURLAuthenticationMethodServerTrust
            ) == .performDefaultHandling
        )
        #expect(
            OpenAIUploadAuthenticationPolicy.decision(
                isActiveTask: true,
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic
            ) == .rejectActiveChallenge
        )
        #expect(
            OpenAIUploadAuthenticationPolicy.decision(
                isActiveTask: false,
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic
            ) == .ignoreSupersededTask
        )
    }

    @Test func crossOriginRedirectsAreRejectedBeforeHeadersOrBodyReachDestination() async throws {
        let destinations = [
            "https://other.example/final",
            "http://upload.example/final",
            "https://upload.example:444/final",
            "https://user:password@upload.example/final",
        ]

        for destination in destinations {
            UploadTestURLProtocol.reset(actions: [
                "/start": .redirect(statusCode: 307, to: URL(string: destination)!),
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

    @Test func totalServiceDeadlineCancelsManualRedirectReplayAndKeepsTimeoutResult() async throws {
        let sourceURL = try makeTemporaryAudio(data: Data("redirect-timeout-audio".utf8))
        let scratchDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-redirect-timeout-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: scratchDirectory)
        }
        UploadTestURLProtocol.reset(actions: [
            "/start": .redirect(
                statusCode: 307,
                to: URL(string: "https://upload.example/final")!
            ),
            "/final": .waitForCancellation,
        ])
        let service = OpenAITranscriptionService(
            requestBuilder: OpenAITranscriptionRequestBuilder(
                endpointURL: URL(string: "https://upload.example/start")!,
                boundary: "Boundary-Redirect-Timeout",
                scratchDirectoryURL: scratchDirectory
            ),
            urlUploader: makeTransport(),
            timeoutSleeper: RedirectReplayStartedTimeoutSleeper(),
            requestTimeout: 3
        )
        let request = try AudioTranscriptionRequest(
            audioFileURL: sourceURL,
            transcriptionConfiguration: .defaults,
            promptComposition: TranscriptionPromptComposition(
                resolvedFreeformPrompt: nil,
                context: nil,
                emojiCommandsConfiguration: EmojiCommandsConfiguration(isEnabled: false),
                customDictionary: .empty
            )
        )

        do {
            _ = try await service.transcribe(
                request,
                credential: OpenAICredential(apiKey: "private-test-key")
            )
            Issue.record("Expected the total provider deadline to win.")
        } catch let error as OpenAITranscriptionServiceError {
            #expect(error == .timedOut)
        } catch {
            Issue.record("Expected OpenAITranscriptionServiceError.timedOut, got \(error)")
        }

        try await waitUntil { UploadTestURLProtocol.waitingStopCount == 1 }
        let observations = UploadTestURLProtocol.observations
        #expect(observations.map(\.url.path) == ["/start", "/final"])
        #expect(observations.allSatisfy { $0.authorization == "Bearer private-test-key" })
        #expect(observations.first?.body == observations.last?.body)
        #expect(try Data(contentsOf: sourceURL) == Data("redirect-timeout-audio".utf8))
    }

    @Test func cancellationAndTimeoutDuringBlockedPreadReturnBeforeDescriptorRead() async throws {
        for expectedError in [
            OpenAITranscriptionServiceError.cancelled,
            .timedOut,
        ] {
            let sourceData = Data(repeating: 0x51, count: 96 * 1024)
            let sourceURL = try makeTemporaryAudio(data: sourceData)
            let scratchDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "holdtype-blocked-pread-\(UUID().uuidString)",
                isDirectory: true
            )
            defer {
                try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
                try? FileManager.default.removeItem(at: scratchDirectory)
            }
            let calls = BlockingPreadPOSIXCalls()
            defer { calls.release() }
            UploadTestURLProtocol.reset(actions: [
                "/v1/audio/transcriptions": .response(
                    statusCode: 200,
                    headers: [:],
                    chunks: [Data(#"{"text":"must be discarded"}"#.utf8)]
                ),
            ])
            let transport = makeTransport()
            let sleeper: any TranscriptionTimeoutSleeping = expectedError == .timedOut
                ? BlockedPreadTimeoutSleeper(calls: calls)
                : NeverTimeoutSleeper()
            let service = OpenAITranscriptionService(
                requestBuilder: OpenAITranscriptionRequestBuilder(
                    endpointURL: URL(
                        string: "https://upload.example/v1/audio/transcriptions"
                    )!,
                    boundary: "Boundary-Blocked-Pread",
                    scratchDirectoryURL: scratchDirectory,
                    fileSystem: POSIXOpenAITranscriptionMultipartFileSystem(calls: calls)
                ),
                urlUploader: transport,
                timeoutSleeper: sleeper,
                requestTimeout: 3
            )
            let probe = UploadTextResultProbe()
            let transcription = Task {
                do {
                    let request = try AudioTranscriptionRequest(
                        audioFileURL: sourceURL,
                        transcriptionConfiguration: .defaults,
                        promptComposition: TranscriptionPromptComposition(
                            resolvedFreeformPrompt: nil,
                            context: nil,
                            emojiCommandsConfiguration: EmojiCommandsConfiguration(
                                isEnabled: false
                            ),
                            customDictionary: .empty
                        )
                    )
                    let credential = try OpenAICredential(apiKey: "private-test-key")
                    probe.complete(
                        .success(
                            try await service.transcribe(request, credential: credential)
                        )
                    )
                } catch {
                    probe.complete(.failure(error))
                }
            }

            try await calls.waitUntilBlocked()
            if expectedError == .cancelled {
                service.cancelActiveTranscription()
            }
            let result = try await probe.waitForResult()
            switch result {
            case .success:
                Issue.record("Expected \(expectedError) before pread returned.")
            case let .failure(error as OpenAITranscriptionServiceError):
                #expect(error == expectedError)
            case let .failure(error):
                Issue.record("Expected OpenAITranscriptionServiceError, got \(error)")
            }

            let descriptor = try #require(calls.blockedFileDescriptor)
            #expect(Darwin.fcntl(descriptor, F_GETFD) != -1)
            #expect(try Data(contentsOf: sourceURL) == sourceData)
            #expect(
                (try? FileManager.default.contentsOfDirectory(atPath: scratchDirectory.path))?
                    .contains(where: { $0.hasSuffix(".multipart") }) != true
            )

            calls.release()
            await transcription.value
            try await waitUntil {
                errno = 0
                return Darwin.fcntl(descriptor, F_GETFD) == -1 && errno == EBADF
            }
        }
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

    @Test func bodyOpenAndReadFailuresRemainTypedLocalMultipartErrors() async throws {
        UploadTestURLProtocol.reset(actions: [
            "/upload": .response(statusCode: 200, headers: [:], chunks: [Data("unused".utf8)]),
        ])
        let bodies: [any OpenAIFileUploadBody] = [
            FailingUploadBody(mode: .open),
            FailingUploadBody(mode: .read),
        ]

        for body in bodies {
            var request = URLRequest(url: URL(string: "https://upload.example/upload")!)
            request.httpMethod = "POST"
            request.setValue("Bearer private-test-key", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=test", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.byteCount), forHTTPHeaderField: "Content-Length")

            await expectMultipartBodyError {
                try await makeTransport().uploadData(for: request, body: body)
            }
        }
    }

    @Test func invalidRequestAndTypedErrorsExposeOnlyRedactedValues() async throws {
        UploadTestURLProtocol.reset(actions: [
            "/private-path": .response(
                statusCode: 200,
                headers: [:],
                chunks: [Data("unsafe".utf8)]
            ),
        ])
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
            ].joined(separator: " ")
            for secret in secretValues {
                #expect(rendered.contains(secret) == false)
            }
        }

        var invalidRequest = URLRequest(url: URL(string: "file:///private-path")!)
        invalidRequest.httpMethod = "POST"
        invalidRequest.setValue("Bearer private-test-key", forHTTPHeaderField: "Authorization")
        let body = TestUploadBody(data: Data("sensitive-request-body".utf8))

        await expectTransportError(.invalidRequest) {
            try await makeTransport().uploadData(for: invalidRequest, body: body)
        }

        var userInfoRequest = URLRequest(
            url: URL(string: "https://user:password@upload.example/private-path")!
        )
        userInfoRequest.httpMethod = "POST"
        userInfoRequest.setValue(
            "Bearer private-test-key",
            forHTTPHeaderField: "Authorization"
        )
        userInfoRequest.setValue(
            "multipart/form-data; boundary=test",
            forHTTPHeaderField: "Content-Type"
        )
        userInfoRequest.setValue(
            String(body.byteCount),
            forHTTPHeaderField: "Content-Length"
        )
        await expectTransportError(.invalidRequest) {
            try await makeTransport().uploadData(for: userInfoRequest, body: body)
        }

        var plaintextRequest = URLRequest(
            url: URL(string: "http://upload.example/private-path")!
        )
        plaintextRequest.httpMethod = "POST"
        plaintextRequest.setValue(
            "Bearer private-test-key",
            forHTTPHeaderField: "Authorization"
        )
        plaintextRequest.setValue(
            "multipart/form-data; boundary=test",
            forHTTPHeaderField: "Content-Type"
        )
        plaintextRequest.setValue(
            String(body.byteCount),
            forHTTPHeaderField: "Content-Length"
        )
        await expectTransportError(.invalidRequest) {
            try await makeTransport().uploadData(for: plaintextRequest, body: body)
        }
        #expect(UploadTestURLProtocol.observations.isEmpty)
        requireSendable(makeTransport())
        requireSendable(OpenAIFileUploadTransportError.cancelled)
    }

    private func upload(to urlString: String) async throws -> (Data, URLResponse) {
        let body = TestUploadBody(data: Data("sensitive-request-body".utf8))

        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.setValue("Bearer private-test-key", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=test", forHTTPHeaderField: "Content-Type")
        request.setValue(String(body.byteCount), forHTTPHeaderField: "Content-Length")
        return try await makeTransport().uploadData(for: request, body: body)
    }

    private func makeTransport() -> OpenAIFileUploadTransport {
        OpenAIFileUploadTransport {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [UploadTestURLProtocol.self]
            return configuration
        }
    }

}

nonisolated private struct TestUploadBody: OpenAIFileUploadBody, Sendable {
    let data: Data

    var byteCount: Int64 { Int64(data.count) }

    func makeInputStream(
        startingAtOffset: Int64,
        failureHandler: @escaping @Sendable (OpenAITranscriptionRequestBuilderError) -> Void
    ) throws -> InputStream {
        guard startingAtOffset >= 0,
              startingAtOffset <= Int64(data.count),
              let offset = Int(exactly: startingAtOffset) else {
            throw OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        }
        return InputStream(data: data.dropFirst(offset))
    }
}

nonisolated private struct FailingUploadBody: OpenAIFileUploadBody, Sendable {
    enum Mode: Sendable {
        case open
        case read
    }

    let mode: Mode
    let byteCount: Int64 = 8

    func makeInputStream(
        startingAtOffset: Int64,
        failureHandler: @escaping @Sendable (OpenAITranscriptionRequestBuilderError) -> Void
    ) throws -> InputStream {
        guard startingAtOffset == 0 else {
            throw OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        }
        switch mode {
        case .open:
            throw OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        case .read:
            return FailingReadInputStream(failureHandler: failureHandler)
        }
    }
}

nonisolated private final class FailingReadInputStream: InputStream, @unchecked Sendable {
    private let failureHandler: @Sendable (OpenAITranscriptionRequestBuilderError) -> Void
    private var status: Stream.Status = .notOpen

    init(
        failureHandler: @escaping @Sendable (OpenAITranscriptionRequestBuilderError) -> Void
    ) {
        self.failureHandler = failureHandler
        super.init(data: Data())
    }

    override func open() {
        status = .open
    }

    override func close() {
        status = .closed
    }

    override func read(
        _ buffer: UnsafeMutablePointer<UInt8>,
        maxLength len: Int
    ) -> Int {
        status = .error
        failureHandler(.multipartBodyUnavailable)
        return -1
    }

    override var hasBytesAvailable: Bool {
        status == .open
    }

    override var streamStatus: Stream.Status {
        status
    }

    override var streamError: (any Error)? {
        status == .error
            ? OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
            : nil
    }
}

nonisolated private final class BlockingPreadPOSIXCalls:
    OpenAITranscriptionPOSIXCalling,
    @unchecked Sendable {
    private enum WaitError: Error {
        case didNotBlock
    }

    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didBlock = false
    private var didRelease = false
    private var storedFileDescriptor: Int32?

    var blockedFileDescriptor: Int32? {
        lock.withLock { storedFileDescriptor }
    }

    func read(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
        Darwin.read(fd, buffer, count)
    }

    func write(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        Darwin.write(fd, buffer, count)
    }

    func synchronize(_ fd: Int32) -> Int32 {
        Darwin.fsync(fd)
    }

    func pread(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int, _ offset: Int64) -> Int {
        let shouldWait = lock.withLock { () -> Bool in
            guard !didBlock else { return false }
            didBlock = true
            storedFileDescriptor = fd
            return !didRelease
        }
        if shouldWait {
            semaphore.wait()
        }
        return Darwin.pread(fd, buffer, count, off_t(offset))
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
}

nonisolated private struct BlockedPreadTimeoutSleeper: TranscriptionTimeoutSleeping {
    let calls: BlockingPreadPOSIXCalls

    func sleep(seconds: TimeInterval) async throws {
        try await calls.waitUntilBlocked()
    }
}

nonisolated private struct NeverTimeoutSleeper: TranscriptionTimeoutSleeping {
    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(60))
    }
}

nonisolated private struct RedirectReplayStartedTimeoutSleeper:
    TranscriptionTimeoutSleeping {
    func sleep(seconds: TimeInterval) async throws {
        try await waitUntil {
            UploadTestURLProtocol.observations.count == 2
        }
    }
}

nonisolated private final class UploadTextResultProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<String, Error>?

    func complete(_ result: Result<String, Error>) {
        lock.withLock {
            guard storedResult == nil else { return }
            storedResult = result
        }
    }

    func waitForResult() async throws -> Result<String, Error> {
        try await waitUntil { [self] in
            lock.withLock { storedResult != nil }
        }
        return try lock.withLock {
            guard let storedResult else { throw UploadTestTimeout() }
            return storedResult
        }
    }
}

nonisolated private func makeTemporaryAudio(data: Data) throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "holdtype-upload-audio-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let fileURL = directoryURL.appendingPathComponent("recording.m4a")
    try data.write(to: fileURL)
    return fileURL
}

nonisolated private func expectTransportError(
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

nonisolated private func expectMultipartBodyError(
    operation: () async throws -> (Data, URLResponse)
) async {
    do {
        _ = try await operation()
        Issue.record("Expected a typed multipart body error.")
    } catch let error as OpenAITranscriptionRequestBuilderError {
        #expect(error == .multipartBodyUnavailable)
    } catch {
        Issue.record("Expected OpenAITranscriptionRequestBuilderError, got \(error)")
    }
}

nonisolated private func assertTransportError(
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

nonisolated private func requireSendable<T: Sendable>(_ value: T) {}

nonisolated private func waitUntil(
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

nonisolated private struct UploadTestTimeout: Error {}

nonisolated private final class UploadResultProbe: @unchecked Sendable {
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

nonisolated private final class UploadTestURLProtocol: URLProtocol {
    enum Action: @unchecked Sendable {
        case response(statusCode: Int, headers: [String: String], chunks: [Data])
        case redirect(statusCode: Int, to: URL)
        case waitForCancellation
        case nonHTTPResponse(chunks: [Data])
        case failure(Error)
    }

    struct Observation: Sendable {
        let url: URL
        let authorization: String?
        let body: Data?
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
        let body: Data?
        do {
            body = try Self.readBody(from: request)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let action = Self.controller.start(
            protocol: self,
            request: request,
            body: body
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        switch action {
        case let .response(statusCode, headers, chunks):
            sendHTTPResponse(statusCode: statusCode, headers: headers, chunks: chunks)
        case let .redirect(statusCode, destination):
            sendRedirect(statusCode: statusCode, to: destination)
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

    private func sendRedirect(statusCode: Int, to destination: URL) {
        guard let sourceURL = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: sourceURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": destination.absoluteString]
        )!
        var redirectedRequest = request
        redirectedRequest.url = destination
        client?.urlProtocol(self, wasRedirectedTo: redirectedRequest, redirectResponse: response)
    }

    private static func readBody(from request: URLRequest) throws -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else {
                throw stream.streamError
                    ?? OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
            }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
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

        func start(
            protocol urlProtocol: UploadTestURLProtocol,
            request: URLRequest,
            body: Data?
        ) -> Action? {
            lock.withLock {
                guard let url = request.url else {
                    return nil
                }
                storedObservations.append(
                    Observation(
                        url: url,
                        authorization: request.value(forHTTPHeaderField: "Authorization"),
                        body: body
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
