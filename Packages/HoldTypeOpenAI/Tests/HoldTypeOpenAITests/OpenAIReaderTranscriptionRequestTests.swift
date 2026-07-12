import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeOpenAI

@MainActor
struct OpenAIReaderTranscriptionRequestTests {
    @Test func requestValidatesNeutralMetadataAndIsRedactedSendableState() throws {
        let composition = promptComposition("private prompt")
        let reader = OpenAITranscriptionAudioReader { _, _ in Data() }
        let request = try OpenAIReaderTranscriptionRequest(
            format: .m4a,
            durationMilliseconds: 1,
            byteCount: 24_999_999,
            model: "gpt-4o-transcribe",
            languageCode: "en",
            promptComposition: composition,
            reader: reader
        )

        requireSendable(request)
        requireSendable(reader)
        #expect(request.format == .m4a)
        #expect(request.durationMilliseconds == 1)
        #expect(request.byteCount == 24_999_999)
        #expect(request.model == "gpt-4o-transcribe")
        #expect(request.languageCode == "en")
        #expect(request.promptComposition == composition)
        #expect(request.description == "OpenAIReaderTranscriptionRequest(<redacted>)")
        #expect(reader.description == "OpenAITranscriptionAudioReader(<redacted>)")
        #expect(!String(reflecting: request).contains("private prompt"))
        #expect(Array(Mirror(reflecting: request).children).isEmpty)
        #expect(Array(Mirror(reflecting: reader).children).isEmpty)
        #expect(((request as Any) is any Encodable) == false)
        #expect(((request as Any) is any Decodable) == false)
        #expect(((reader as Any) is any Encodable) == false)
        #expect(((reader as Any) is any Decodable) == false)
        var requestDump = ""
        dump(request, to: &requestDump)
        #expect(!requestDump.contains("private prompt"))
        #expect(!requestDump.contains("gpt-4o-transcribe"))

        for duration in [Int64.min, -1, 0, 300_000, Int64.max] {
            #expect(
                throws: OpenAIReaderTranscriptionRequest.ValidationError
                    .invalidDurationMilliseconds
            ) {
                _ = try makeRequest(
                    durationMilliseconds: duration,
                    reader: OpenAITranscriptionAudioReader { _, _ in Data() }
                )
            }
        }
        for byteCount in [Int64.min, -1, 0, 25_000_000, Int64.max] {
            #expect(
                throws: OpenAIReaderTranscriptionRequest.ValidationError
                    .invalidByteCount
            ) {
                _ = try makeRequest(
                    byteCount: byteCount,
                    reader: OpenAITranscriptionAudioReader { _, _ in Data() }
                )
            }
        }
        for model in ["", " ", " model", "model\n"] {
            #expect(
                throws: OpenAIReaderTranscriptionRequest.ValidationError.invalidModel
            ) {
                _ = try makeRequest(
                    model: model,
                    reader: OpenAITranscriptionAudioReader { _, _ in Data() }
                )
            }
        }
        for language in ["e", "engl", "EN", "e1", "éñ"] {
            #expect(
                throws: OpenAIReaderTranscriptionRequest.ValidationError
                    .invalidLanguageCode
            ) {
                _ = try makeRequest(
                    languageCode: language,
                    reader: OpenAITranscriptionAudioReader { _, _ in Data() }
                )
            }
        }

        _ = try makeRequest(
            format: .wav,
            durationMilliseconds: 299_999,
            byteCount: 1,
            languageCode: nil,
            reader: OpenAITranscriptionAudioReader { _, _ in Data() }
        )
        _ = try makeRequest(
            languageCode: "rus",
            reader: OpenAITranscriptionAudioReader { _, _ in Data() }
        )
    }

    @Test func readerMultipartUsesExactFieldsBoundedOffsetsAndControlledFormats() async throws {
        for format in OpenAIReaderTranscriptionRequest.AudioFormat.allCases {
            let audio = Data((0..<(140 * 1_024 + 7)).map { UInt8($0 % 251) })
            let reads = ReaderReadLog()
            let reader = OpenAITranscriptionAudioReader { offset, maximumByteCount in
                reads.record(offset: offset, maximumByteCount: maximumByteCount)
                guard offset < audio.count else { return Data() }
                let start = Int(offset)
                let end = min(start + maximumByteCount, audio.count)
                return audio[start..<end]
            }
            let request = try makeRequest(
                format: format,
                durationMilliseconds: 2_500,
                byteCount: Int64(audio.count),
                model: "reader-model",
                languageCode: "ru",
                composition: promptComposition("reader prompt"),
                reader: reader
            )
            let scratchDirectory = temporaryDirectory("reader-exact-\(format)")
            defer { remove(scratchDirectory) }
            let builder = OpenAITranscriptionRequestBuilder(
                boundary: "Boundary-Reader",
                scratchDirectoryURL: scratchDirectory
            )
            let cleanup = builder.makeCleanupRegistration()
            let preparation = try await builder.makePreparation(
                request,
                cleanupRegistration: cleanup
            )
            defer {
                preparation.cleanup()
                cleanup.requestCleanup()
            }

            let prepared = try await preparation.prepareRequest()
            let body = try readAll(prepared.body)
            let expectedFileName = format == .m4a ? "recording.m4a" : "recording.wav"
            let expectedContentType = format == .m4a ? "audio/mp4" : "audio/wav"
            var expected = Data(
                (
                    "--Boundary-Reader\r\n"
                        + "Content-Disposition: form-data; name=\"model\"\r\n\r\n"
                        + "reader-model\r\n"
                        + "--Boundary-Reader\r\n"
                        + "Content-Disposition: form-data; name=\"response_format\"\r\n\r\n"
                        + "json\r\n"
                        + "--Boundary-Reader\r\n"
                        + "Content-Disposition: form-data; name=\"language\"\r\n\r\n"
                        + "ru\r\n"
                        + "--Boundary-Reader\r\n"
                        + "Content-Disposition: form-data; name=\"prompt\"\r\n\r\n"
                        + "reader prompt\r\n"
                        + "--Boundary-Reader\r\n"
                        + "Content-Disposition: form-data; name=\"file\"; filename=\""
                        + expectedFileName
                        + "\"\r\nContent-Type: "
                        + expectedContentType
                        + "\r\n\r\n"
                ).utf8
            )
            expected.append(audio)
            expected.append(Data("\r\n--Boundary-Reader--\r\n".utf8))

            #expect(body == expected)
            #expect(prepared.request.httpBody == nil)
            #expect(prepared.request.httpBodyStream == nil)
            #expect(
                prepared.request.value(forHTTPHeaderField: "Content-Length")
                    == String(expected.count)
            )
            #expect(!FileManager.default.fileExists(atPath: preparation.bodyFileURL.path))
            #expect(reads.maximumRequestedByteCount == 64 * 1_024)
            #expect(reads.calls.allSatisfy { $0.maximumByteCount <= 64 * 1_024 })
            #expect(reads.calls.last?.offset == Int64(audio.count))
            #expect(reads.calls.last?.maximumByteCount == 1)
            #expect(reads.calls.dropLast().map(\.offset) == [0, 65_536, 131_072])
        }
    }

    @Test func readerAllowsShortChunksButRejectsEarlyEOFOverflowAndTrailingData() async throws {
        let audio = Data((0..<100).map(UInt8.init))
        let shortReader = OpenAITranscriptionAudioReader { offset, maximumByteCount in
            guard offset < audio.count else { return Data() }
            let start = Int(offset)
            let end = min(start + min(maximumByteCount, 7), audio.count)
            return audio[start..<end]
        }
        let shortPreparation = try await makePreparation(
            try makeRequest(
                byteCount: Int64(audio.count),
                reader: shortReader
            ),
            suffix: "short"
        )
        defer {
            shortPreparation.preparation.cleanup()
            shortPreparation.cleanup.requestCleanup()
            remove(shortPreparation.directory)
        }
        let shortBody = try readAll(
            try await shortPreparation.preparation.prepareRequest().body
        )
        #expect(shortBody.contains(audio))

        let earlyEOF = OpenAITranscriptionAudioReader { _, _ in Data() }
        let earlyPreparation = try await makePreparation(
            try makeRequest(byteCount: 4, reader: earlyEOF),
            suffix: "early"
        )
        defer {
            earlyPreparation.preparation.cleanup()
            earlyPreparation.cleanup.requestCleanup()
            remove(earlyPreparation.directory)
        }
        await #expect(
            throws: OpenAITranscriptionRequestBuilderError.audioReaderChanged
        ) {
            _ = try await earlyPreparation.preparation.prepareRequest()
        }

        let oversized = OpenAITranscriptionAudioReader { _, maximumByteCount in
            Data(repeating: 1, count: maximumByteCount + 1)
        }
        let oversizedPreparation = try await makePreparation(
            try makeRequest(byteCount: 4, reader: oversized),
            suffix: "oversized"
        )
        defer {
            oversizedPreparation.preparation.cleanup()
            oversizedPreparation.cleanup.requestCleanup()
            remove(oversizedPreparation.directory)
        }
        await #expect(
            throws: OpenAITranscriptionRequestBuilderError.audioReaderChanged
        ) {
            _ = try await oversizedPreparation.preparation.prepareRequest()
        }

        let trailing = OpenAITranscriptionAudioReader { offset, maximumByteCount in
            if offset < audio.count {
                let start = Int(offset)
                let end = min(start + maximumByteCount, audio.count)
                return audio[start..<end]
            }
            return Data([0xFF])
        }
        let trailingPreparation = try await makePreparation(
            try makeRequest(byteCount: Int64(audio.count), reader: trailing),
            suffix: "trailing"
        )
        defer {
            trailingPreparation.preparation.cleanup()
            trailingPreparation.cleanup.requestCleanup()
            remove(trailingPreparation.directory)
        }
        await #expect(
            throws: OpenAITranscriptionRequestBuilderError.audioReaderChanged
        ) {
            _ = try await trailingPreparation.preparation.prepareRequest()
        }
    }

    @Test func readerFailureIsTypedAndReaderCanBeConsumedOnlyOnce() async throws {
        struct ReadFailure: Error {}

        let failingRequest = try makeRequest(
            byteCount: 4,
            reader: OpenAITranscriptionAudioReader { _, _ in throw ReadFailure() }
        )
        let failingPreparation = try await makePreparation(
            failingRequest,
            suffix: "unreadable"
        )
        defer {
            failingPreparation.preparation.cleanup()
            failingPreparation.cleanup.requestCleanup()
            remove(failingPreparation.directory)
        }
        await #expect(
            throws: OpenAITranscriptionRequestBuilderError.audioReaderUnreadable
        ) {
            _ = try await failingPreparation.preparation.prepareRequest()
        }

        let request = try makeRequest(
            byteCount: 4,
            reader: OpenAITranscriptionAudioReader { offset, maximumByteCount in
                guard offset < 4 else { return Data() }
                return Data(repeating: 1, count: min(maximumByteCount, 4 - Int(offset)))
            }
        )
        let first = try await makePreparation(request, suffix: "once-first")
        defer {
            first.preparation.cleanup()
            first.cleanup.requestCleanup()
            remove(first.directory)
        }
        let secondDirectory = temporaryDirectory("reader-once-second")
        defer { remove(secondDirectory) }
        let secondBuilder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Once",
            scratchDirectoryURL: secondDirectory
        )
        await #expect(
            throws: OpenAITranscriptionRequestBuilderError.audioReaderAlreadyConsumed
        ) {
            _ = try await secondBuilder.makePreparation(
                request,
                cleanupRegistration: secondBuilder.makeCleanupRegistration()
            )
        }
        #expect(!FileManager.default.fileExists(atPath: secondDirectory.path))
    }

    @Test func invalidBoundaryAndOversizedMetadataFailBeforeReaderClaimOrScratch() async throws {
        for failure in ["boundary", "metadata"] {
            let reads = ReaderReadLog()
            let reader = OpenAITranscriptionAudioReader { offset, maximumByteCount in
                reads.record(offset: offset, maximumByteCount: maximumByteCount)
                return Data()
            }
            let request = try makeRequest(
                composition: failure == "metadata"
                    ? promptComposition(String(repeating: "x", count: 1_048_577))
                    : promptComposition(nil),
                reader: reader
            )
            let directory = temporaryDirectory("reader-preclaim-\(failure)")
            defer { remove(directory) }
            let builder = OpenAITranscriptionRequestBuilder(
                boundary: failure == "boundary" ? "bad\r\nboundary" : "Boundary-Metadata",
                scratchDirectoryURL: directory
            )

            do {
                _ = try await builder.makePreparation(
                    request,
                    cleanupRegistration: builder.makeCleanupRegistration()
                )
                Issue.record("Expected \(failure) validation failure.")
            } catch let error as OpenAITranscriptionRequestBuilderError {
                switch (failure, error) {
                case ("boundary", .invalidMultipartBoundary),
                     ("metadata", .multipartMetadataTooLarge):
                    break
                default:
                    Issue.record("Unexpected \(failure) error: \(error)")
                }
            }

            #expect(reads.calls.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: directory.path))
            let lease = try request.claimReader()
            lease.retire()
        }
    }

    @Test func completedPreparationReleasesReaderCaptureWhileRequestRemainsAlive() async throws {
        final class RetainedProbe: @unchecked Sendable {}

        var probe: RetainedProbe? = RetainedProbe()
        let weakProbe = WeakReaderTestReference(probe)
        let audio = Data([1, 2, 3, 4])
        let reader = OpenAITranscriptionAudioReader { [probe] offset, maximumByteCount in
            _ = probe
            guard offset < audio.count else { return Data() }
            let start = Int(offset)
            return audio[start..<min(start + maximumByteCount, audio.count)]
        }
        let request = try makeRequest(byteCount: Int64(audio.count), reader: reader)
        probe = nil
        #expect(weakProbe.value != nil)

        let context = try await makePreparation(request, suffix: "release")
        defer {
            context.preparation.cleanup()
            context.cleanup.requestCleanup()
            remove(context.directory)
        }
        _ = try await context.preparation.prepareRequest()
        #expect(weakProbe.value == nil)
        #expect(request.byteCount == 4)
    }

    @Test func serviceTranscribesReaderWithoutLiveNetworkAndPreservesPromptGuards() async throws {
        let audio = Data("reader audio".utf8)
        let uploader = ReaderTestUploader(
            result: .success(
                Data(#"{"text":"accepted reader transcript"}"#.utf8),
                try httpResponse(statusCode: 200)
            )
        )
        let sleeper = ReaderTestTimeoutSleeper(mode: .waitForCancellation)
        let scratchDirectory = temporaryDirectory("reader-service")
        defer { remove(scratchDirectory) }
        let service = OpenAITranscriptionService(
            requestBuilder: OpenAITranscriptionRequestBuilder(
                boundary: "Boundary-Service-Reader",
                scratchDirectoryURL: scratchDirectory
            ),
            urlUploader: uploader,
            timeoutSleeper: sleeper,
            requestTimeout: 9
        )
        let request = try makeRequest(
            byteCount: Int64(audio.count),
            composition: promptComposition("provider prompt"),
            reader: dataReader(audio)
        )

        let transcript = try await service.transcribe(
            request,
            credential: try OpenAICredential(apiKey: "sk-reader-test")
        )

        #expect(transcript == "accepted reader transcript")
        #expect(uploader.requests.count == 1)
        #expect(uploader.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer sk-reader-test")
        #expect(uploader.uploadedBodies.count == 1)
        #expect(uploader.uploadedBodies[0].contains(audio))
        #expect(sleeper.sleepCalls == [9])
    }

    @Test func serviceRetiresReaderWhenDeadlineWinsDuringPreparation() async throws {
        let reads = ReaderReadLog()
        let request = try makeRequest(
            reader: OpenAITranscriptionAudioReader { offset, maximumByteCount in
                reads.record(offset: offset, maximumByteCount: maximumByteCount)
                return Data()
            }
        )
        let uploader = ReaderTestUploader(
            result: .success(
                Data(#"{"text":"must not upload"}"#.utf8),
                try httpResponse(statusCode: 200)
            )
        )
        let scratchDirectory = temporaryDirectory("reader-immediate-deadline")
        defer { remove(scratchDirectory) }
        let service = OpenAITranscriptionService(
            requestBuilder: OpenAITranscriptionRequestBuilder(
                boundary: "Boundary-Immediate-Deadline",
                scratchDirectoryURL: scratchDirectory
            ),
            urlUploader: uploader,
            timeoutSleeper: ReaderTestTimeoutSleeper(mode: .failImmediately),
            requestTimeout: 5
        )

        await #expect(throws: OpenAITranscriptionServiceError.timedOut) {
            _ = try await service.transcribe(
                request,
                credential: try OpenAICredential(apiKey: "sk-immediate-timeout")
            )
        }
        #expect(throws: OpenAITranscriptionAudioReaderError.alreadyConsumed) {
            _ = try request.claimReader()
        }
        #expect(uploader.requests.isEmpty)
        try await waitForCondition {
            guard FileManager.default.fileExists(atPath: scratchDirectory.path) else {
                return true
            }
            let names = try? FileManager.default.contentsOfDirectory(
                atPath: scratchDirectory.path
            )
            return names?.contains(where: { $0.hasSuffix(".multipart") }) == false
        }
    }

    @Test func timeoutAndCancellationReturnBeforeBlockedReaderAndNeverUpload() async throws {
        for mode in ReaderInterruptionMode.allCases {
            let expectedError = mode == .timeout
                ? OpenAITranscriptionServiceError.timedOut
                : OpenAITranscriptionServiceError.cancelled
            let blocker = BlockingReader()
            defer { blocker.release() }
            let uploader = ReaderTestUploader(
                result: .success(
                    Data(#"{"text":"must not upload"}"#.utf8),
                    try httpResponse(statusCode: 200)
                )
            )
            let sleeper = ReaderTestTimeoutSleeper(
                mode: mode == .timeout
                    ? .failAfterReaderStarts(blocker)
                    : .waitForCancellation
            )
            let scratchDirectory = temporaryDirectory("reader-blocked-\(expectedError)")
            defer { remove(scratchDirectory) }
            let service = OpenAITranscriptionService(
                requestBuilder: OpenAITranscriptionRequestBuilder(
                    boundary: "Boundary-Blocked-Reader",
                    scratchDirectoryURL: scratchDirectory
                ),
                urlUploader: uploader,
                timeoutSleeper: sleeper,
                requestTimeout: 11
            )
            let request = try makeRequest(
                byteCount: 4,
                reader: OpenAITranscriptionAudioReader { offset, maximumByteCount in
                    try await blocker.read(offset: offset, maximumByteCount: maximumByteCount)
                }
            )
            let result = AsyncReaderResultProbe<String>()
            let task = Task {
                do {
                    result.complete(
                        .success(
                            try await service.transcribe(
                                request,
                                credential: try OpenAICredential(apiKey: "sk-blocked-reader")
                            )
                        )
                    )
                } catch {
                    result.complete(.failure(error))
                }
            }

            try await blocker.waitUntilStarted()
            if mode == .explicitCancellation {
                service.cancelActiveTranscription()
            } else if mode == .parentCancellation {
                task.cancel()
            }
            let completion = try await result.waitForResult()
            switch completion {
            case .success:
                Issue.record("Expected blocked reader to finish with \(expectedError).")
            case .failure(let error as OpenAITranscriptionServiceError):
                #expect(error == expectedError)
            case .failure(let error):
                Issue.record("Expected OpenAITranscriptionServiceError, got \(error)")
            }
            #expect(uploader.requests.isEmpty)
            try await waitForCondition {
                guard FileManager.default.fileExists(atPath: scratchDirectory.path) else {
                    return true
                }
                let names = try? FileManager.default.contentsOfDirectory(
                    atPath: scratchDirectory.path
                )
                return names?.contains(where: { $0.hasSuffix(".multipart") }) == false
            }

            blocker.release()
            await task.value
            #expect(uploader.requests.isEmpty)
        }
    }

    private func makeRequest(
        format: OpenAIReaderTranscriptionRequest.AudioFormat = .m4a,
        durationMilliseconds: Int64 = 1_000,
        byteCount: Int64 = 4,
        model: String = "gpt-4o-transcribe",
        languageCode: String? = nil,
        composition: TranscriptionPromptComposition = promptComposition(nil),
        reader: OpenAITranscriptionAudioReader
    ) throws -> OpenAIReaderTranscriptionRequest {
        try OpenAIReaderTranscriptionRequest(
            format: format,
            durationMilliseconds: durationMilliseconds,
            byteCount: byteCount,
            model: model,
            languageCode: languageCode,
            promptComposition: composition,
            reader: reader
        )
    }

    private func makePreparation(
        _ request: OpenAIReaderTranscriptionRequest,
        suffix: String
    ) async throws -> (
        preparation: OpenAIReaderTranscriptionMultipartPreparation,
        cleanup: OpenAITranscriptionMultipartCleanupRegistration,
        directory: URL
    ) {
        let directory = temporaryDirectory("reader-\(suffix)")
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-\(suffix)",
            scratchDirectoryURL: directory
        )
        let cleanup = builder.makeCleanupRegistration()
        let preparation = try await builder.makePreparation(
            request,
            cleanupRegistration: cleanup
        )
        return (preparation, cleanup, directory)
    }
}

private func promptComposition(_ prompt: String?) -> TranscriptionPromptComposition {
    TranscriptionPromptComposition(
        resolvedFreeformPrompt: prompt,
        context: nil,
        emojiCommandsConfiguration: EmojiCommandsConfiguration(isEnabled: false),
        customDictionary: .empty
    )
}

private func dataReader(_ data: Data) -> OpenAITranscriptionAudioReader {
    OpenAITranscriptionAudioReader { offset, maximumByteCount in
        guard offset < data.count else { return Data() }
        let start = Int(offset)
        let end = min(start + maximumByteCount, data.count)
        return data[start..<end]
    }
}

private func requireSendable<T: Sendable>(_: T) {}

private final class ReaderReadLog: @unchecked Sendable {
    struct Call: Equatable, Sendable {
        let offset: Int64
        let maximumByteCount: Int
    }

    private let lock = NSLock()
    private var storedCalls: [Call] = []

    var calls: [Call] { lock.withLock { storedCalls } }
    var maximumRequestedByteCount: Int {
        lock.withLock { storedCalls.map(\.maximumByteCount).max() ?? 0 }
    }

    func record(offset: Int64, maximumByteCount: Int) {
        lock.withLock {
            storedCalls.append(Call(offset: offset, maximumByteCount: maximumByteCount))
        }
    }
}

private func temporaryDirectory(_ suffix: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "holdtype-openai-reader-\(suffix)-\(UUID().uuidString)",
        isDirectory: true
    )
}

private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func readAll(_ body: any OpenAIFileUploadBody) throws -> Data {
    let stream = try body.makeInputStream { _ in }
    stream.open()
    defer { stream.close() }

    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else {
            throw stream.streamError
                ?? OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        }
        if count == 0 { break }
        result.append(contentsOf: buffer.prefix(count))
    }
    return result
}

private func httpResponse(statusCode: Int) throws -> HTTPURLResponse {
    try #require(
        HTTPURLResponse(
            url: OpenAITranscriptionRequestBuilder.defaultEndpointURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )
    )
}

private final class ReaderTestUploader: URLFileUploading, @unchecked Sendable {
    enum Result {
        case success(Data, URLResponse)
        case failure(any Error)
    }

    private let result: Result
    private let lock = NSLock()
    private var storedRequests: [URLRequest] = []
    private var storedUploadedBodies: [Data] = []

    var requests: [URLRequest] { lock.withLock { storedRequests } }
    var uploadedBodies: [Data] { lock.withLock { storedUploadedBodies } }

    init(result: Result) {
        self.result = result
    }

    func uploadData(
        for request: URLRequest,
        body: any OpenAIFileUploadBody
    ) async throws -> (Data, URLResponse) {
        let data = try readAll(body)
        lock.withLock {
            storedRequests.append(request)
            storedUploadedBodies.append(data)
        }
        switch result {
        case .success(let data, let response):
            return (data, response)
        case .failure(let error):
            throw error
        }
    }
}

private final class ReaderTestTimeoutSleeper:
    TranscriptionTimeoutSleeping,
    @unchecked Sendable {
    enum Mode {
        case waitForCancellation
        case failAfterReaderStarts(BlockingReader)
        case failImmediately
    }

    private let mode: Mode
    private let lock = NSLock()
    private var storedSleepCalls: [TimeInterval] = []

    var sleepCalls: [TimeInterval] { lock.withLock { storedSleepCalls } }

    init(mode: Mode) {
        self.mode = mode
    }

    func sleep(seconds: TimeInterval) async throws {
        lock.withLock { storedSleepCalls.append(seconds) }
        switch mode {
        case .waitForCancellation:
            try await Task.sleep(for: .seconds(60))
        case .failAfterReaderStarts(let blocker):
            try await blocker.waitUntilStarted()
            throw OpenAITranscriptionServiceError.timedOut
        case .failImmediately:
            throw OpenAITranscriptionServiceError.timedOut
        }
    }
}

private final class BlockingReader: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func read(offset _: Int64, maximumByteCount _: Int) async throws -> Data {
        lock.withLock { started = true }
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if released { return true }
                self.continuation = continuation
                return false
            }
            if shouldResume { continuation.resume() }
        }
        return Data([1, 2, 3, 4])
    }

    func waitUntilStarted() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !lock.withLock({ started }) {
            guard clock.now < deadline else { throw ReaderTestWaitError.timedOut }
            try await clock.sleep(for: .milliseconds(1))
        }
    }

    func release() {
        let continuation = lock.withLock {
            released = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }
}

private final class AsyncReaderResultProbe<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, any Error>?

    func complete(_ result: Result<Value, any Error>) {
        lock.withLock { self.result = result }
    }

    func waitForResult() async throws -> Result<Value, any Error> {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while true {
            if let result = lock.withLock({ result }) { return result }
            guard clock.now < deadline else { throw ReaderTestWaitError.timedOut }
            try await clock.sleep(for: .milliseconds(1))
        }
    }
}

private enum ReaderTestWaitError: Error {
    case timedOut
}

private enum ReaderInterruptionMode: CaseIterable {
    case timeout
    case explicitCancellation
    case parentCancellation
}

private final class WeakReaderTestReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

@MainActor
private func waitForCondition(
    _ condition: @escaping () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    while !condition() {
        guard clock.now < deadline else { throw ReaderTestWaitError.timedOut }
        try await clock.sleep(for: .milliseconds(1))
    }
}
