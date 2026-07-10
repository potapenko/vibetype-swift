import Darwin
import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeOpenAI

@MainActor
struct OpenAITranscriptionRequestBuilderTests {
    @Test func exactFileBackedBodyUsesControlledFilenameAndNoRequestBody() async throws {
        let audio = Data([0, 65, 255, 10])
        let source = try temporaryAudio(named: "secret\"\r\nInjected.m4a", data: audio)
        let scratchDirectory = temporaryDirectory("multipart-exact")
        defer { remove(source.deletingLastPathComponent()); remove(scratchDirectory) }
        let transcriptionConfiguration = TranscriptionConfiguration(
            model: "custom-model",
            language: .english,
            freeformPrompt: "  product names  "
        )
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Test",
            scratchDirectoryURL: scratchDirectory
        )
        let (preparation, cleanup) = try await prepare(
            builder,
            request: try request(
                source,
                transcriptionConfiguration: transcriptionConfiguration,
                emojiCommandsConfiguration: EmojiCommandsConfiguration(isEnabled: false)
            )
        )
        defer { preparation.cleanup(); cleanup.requestCleanup() }

        let scratchAttributes = try FileManager.default.attributesOfItem(
            atPath: preparation.bodyFileURL.path
        )
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: scratchDirectory.path
        )
        let scratchResourceValues = try preparation.bodyFileURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        let directoryResourceValues = try scratchDirectory.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        #expect((scratchAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(scratchResourceValues.isExcludedFromBackup == true)
        #expect(directoryResourceValues.isExcludedFromBackup == true)
#if os(iOS)
        let scratchProtection = scratchAttributes[.protectionKey] as? FileProtectionType
        let directoryProtection = directoryAttributes[.protectionKey] as? FileProtectionType
#if targetEnvironment(simulator)
        #expect(scratchProtection == nil || scratchProtection == .complete)
        #expect(directoryProtection == nil || directoryProtection == .complete)
#else
        #expect(scratchProtection == .complete)
        #expect(directoryProtection == .complete)
#endif
#endif

        let preparedUpload = try await preparation.prepareRequest()
        let urlRequest = preparedUpload.request
        let body = try readAll(preparedUpload.body)
        #expect(!FileManager.default.fileExists(atPath: preparation.bodyFileURL.path))
        var expected = Data(
            "--Boundary-Test\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\ncustom-model\r\n".utf8
        )
        expected.append(
            Data(
                (
                    "--Boundary-Test\r\nContent-Disposition: form-data; "
                        + "name=\"response_format\"\r\n\r\njson\r\n"
                ).utf8
            )
        )
        expected.append(
            Data(
                (
                    "--Boundary-Test\r\nContent-Disposition: form-data; "
                        + "name=\"language\"\r\n\r\nen\r\n"
                ).utf8
            )
        )
        expected.append(
            Data(
                (
                    "--Boundary-Test\r\nContent-Disposition: form-data; "
                        + "name=\"prompt\"\r\n\r\nproduct names\r\n"
                ).utf8
            )
        )
        expected.append(
            Data(
                (
                    "--Boundary-Test\r\nContent-Disposition: form-data; name=\"file\"; "
                        + "filename=\"recording.m4a\"\r\n"
                        + "Content-Type: audio/mp4\r\n\r\n"
                ).utf8
            )
        )
        expected.append(audio)
        expected.append(Data("\r\n--Boundary-Test--\r\n".utf8))

        #expect(body == expected)
        #expect(urlRequest.httpBody == nil)
        #expect(urlRequest.httpBodyStream == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Length") == String(body.count))
        #expect(!body.contains(Data("secret".utf8)))
        #expect(!body.contains(Data("Injected".utf8)))
        #expect(try Data(contentsOf: source) == audio)
    }

    @Test func rejectsMissingNonregularSymlinkEmptyUnsupportedAndExclusiveLimit() async throws {
        let sourceURL = URL(fileURLWithPath: "/private/source.m4a")
        let validIdentity = testIdentity(byteCount: 4)
        typealias TestCase = (
            openResult: Result<any OpenAITranscriptionAudioSource, Error>,
            sourceURL: URL,
            expectedError: OpenAITranscriptionRequestBuilderError
        )
        let cases: [TestCase] = [
            (
                .failure(OpenAITranscriptionMultipartFileSystemError.missingSource),
                sourceURL,
                .missingAudioFile(sourceURL)
            ),
            (
                .failure(OpenAITranscriptionMultipartFileSystemError.invalidSource),
                sourceURL,
                .unreadableAudioFile(sourceURL)
            ),
            (
                .success(FakeAudioSource(identity: testIdentity(byteCount: 0))),
                sourceURL,
                .emptyAudioFile(sourceURL)
            ),
            (
                .success(FakeAudioSource(identity: validIdentity)),
                URL(fileURLWithPath: "/private/source.txt"),
                .unsupportedAudioFileType("txt")
            ),
            (
                .success(FakeAudioSource(identity: testIdentity(byteCount: 25_000_000))),
                sourceURL,
                .audioFileTooLarge(byteCount: 25_000_000, maximumExclusive: 25_000_000)
            ),
        ]
        for (openResult, url, expected) in cases {
            let fileSystem = FakeMultipartFileSystem(openResult: openResult)
            let builder = OpenAITranscriptionRequestBuilder(fileSystem: fileSystem)
            let cleanup = builder.makeCleanupRegistration()
            await #expect(throws: expected) {
                _ = try await builder.makePreparation(
                    try request(url),
                    cleanupRegistration: cleanup
                )
            }
            #expect(fileSystem.createdScratchCount == 0)
        }

        let acceptedFileSystem = FakeMultipartFileSystem(
            openResult: .success(
                FakeAudioSource(identity: testIdentity(byteCount: 24_999_999))
            )
        )
        let acceptedBuilder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Maximum-Audio",
            fileSystem: acceptedFileSystem
        )
        let acceptedCleanup = acceptedBuilder.makeCleanupRegistration()
        let acceptedPreparation = try await acceptedBuilder.makePreparation(
            try request(sourceURL),
            cleanupRegistration: acceptedCleanup
        )
        acceptedPreparation.cleanup()
        acceptedCleanup.requestCleanup()
        #expect(acceptedFileSystem.createdScratchCount == 1)
    }

    @Test func productionRejectsDirectoryAndSymbolicLinkSources() async throws {
        let rootDirectory = temporaryDirectory("invalid-sources")
        let scratchDirectory = temporaryDirectory("invalid-source-scratch")
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        defer {
            remove(rootDirectory)
            remove(scratchDirectory)
        }

        let targetURL = rootDirectory.appendingPathComponent("target.m4a")
        try Data("audio".utf8).write(to: targetURL)
        let symbolicLinkURL = rootDirectory.appendingPathComponent("link.m4a")
        try FileManager.default.createSymbolicLink(
            at: symbolicLinkURL,
            withDestinationURL: targetURL
        )
        let directoryURL = rootDirectory.appendingPathComponent(
            "directory.m4a",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false
        )
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Invalid-Source",
            scratchDirectoryURL: scratchDirectory
        )

        for sourceURL in [symbolicLinkURL, directoryURL] {
            await #expect(
                throws: OpenAITranscriptionRequestBuilderError.unreadableAudioFile(sourceURL)
            ) {
                _ = try await builder.makePreparation(
                    try request(sourceURL),
                    cleanupRegistration: builder.makeCleanupRegistration()
                )
            }
        }

        #expect(!FileManager.default.fileExists(atPath: scratchDirectory.path))
    }

    @Test func unsafeMultipartBoundariesAreRejectedBeforeFileIO() async throws {
        let sourceURL = URL(fileURLWithPath: "/private/source.m4a")
        for boundary in ["", "Boundary\r\nInjected", String(repeating: "a", count: 71)] {
            let fileSystem = FakeMultipartFileSystem(
                openResult: .success(FakeAudioSource(identity: testIdentity(byteCount: 4)))
            )
            let builder = OpenAITranscriptionRequestBuilder(
                boundary: boundary,
                fileSystem: fileSystem
            )

            await #expect(
                throws: OpenAITranscriptionRequestBuilderError.invalidMultipartBoundary
            ) {
                _ = try await builder.makePreparation(
                    try request(sourceURL),
                    cleanupRegistration: builder.makeCleanupRegistration()
                )
            }
            #expect(fileSystem.openedSourceCount == 0)
            #expect(fileSystem.createdScratchCount == 0)
        }
    }

    @Test func symbolicLinkScratchNamespaceFailsWithoutEscapingOrTouchingSource() async throws {
        let sourceData = Data("audio".utf8)
        let sourceURL = try temporaryAudio(data: sourceData)
        let rootDirectory = temporaryDirectory("scratch-symlink")
        let targetDirectory = rootDirectory.appendingPathComponent("target", isDirectory: true)
        let symbolicLinkDirectory = rootDirectory.appendingPathComponent("scratch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: targetDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: symbolicLinkDirectory,
            withDestinationURL: targetDirectory
        )
        defer {
            remove(sourceURL.deletingLastPathComponent())
            remove(rootDirectory)
        }
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Scratch-Symlink",
            scratchDirectoryURL: symbolicLinkDirectory
        )

        await #expect(
            throws: OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        ) {
            _ = try await builder.makePreparation(
                try request(sourceURL),
                cleanupRegistration: builder.makeCleanupRegistration()
            )
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: targetDirectory.path).isEmpty)
        #expect(try Data(contentsOf: sourceURL) == sourceData)
    }

    @Test func metadataBudgetAcceptsExactOneMiBAndRejectsOneByteMoreBeforeScratch() async throws {
        let identity = testIdentity(byteCount: 4)
        let baseFileSystem = FakeMultipartFileSystem(
            openResult: .success(FakeAudioSource(identity: identity, data: Data(repeating: 1, count: 4)))
        )
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Budget",
            fileSystem: baseFileSystem
        )
        let baseComposition = TranscriptionPromptComposition(
            resolvedFreeformPrompt: "x",
            context: nil,
            emojiCommandsConfiguration: EmojiCommandsConfiguration(isEnabled: false),
            customDictionary: .empty
        )
        let baseRequest = try AudioTranscriptionRequest(
            audioFileURL: URL(fileURLWithPath: "/private/source.m4a"),
            transcriptionConfiguration: .defaults,
            promptComposition: baseComposition
        )
        let (basePreparation, baseCleanup) = try await prepare(builder, request: baseRequest)
        let baseURLRequest = try await basePreparation.prepareRequest().request
        let baseTotal = try #require(
            Int64(baseURLRequest.value(forHTTPHeaderField: "Content-Length") ?? "")
        )
        let baseMetadata = baseTotal - identity.byteCount
        basePreparation.cleanup()
        baseCleanup.requestCleanup()

        let exactPromptCount = Int(
            OpenAITranscriptionRequestBuilder.maximumMetadataByteCount - baseMetadata + 1
        )
        let exactPrompt = String(repeating: "x", count: exactPromptCount)
        let exactFS = FakeMultipartFileSystem(
            openResult: .success(
                FakeAudioSource(
                    identity: identity,
                    data: Data(repeating: 1, count: 4)
                )
            )
        )
        let exactBuilder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Budget",
            fileSystem: exactFS
        )
        let exact = try AudioTranscriptionRequest(
            audioFileURL: baseRequest.audioFileURL,
            transcriptionConfiguration: .defaults,
            promptComposition: .init(
                resolvedFreeformPrompt: exactPrompt,
                context: nil,
                emojiCommandsConfiguration: EmojiCommandsConfiguration(isEnabled: false),
                customDictionary: .empty
            )
        )
        let (exactPreparation, exactCleanup) = try await prepare(exactBuilder, request: exact)
        defer { exactPreparation.cleanup(); exactCleanup.requestCleanup() }
        _ = try await exactPreparation.prepareRequest()
        #expect(exactFS.createdScratchCount == 1)

        let oversizedFS = FakeMultipartFileSystem(
            openResult: .success(FakeAudioSource(identity: identity))
        )
        let oversizedBuilder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Budget",
            fileSystem: oversizedFS
        )
        let oversized = try AudioTranscriptionRequest(
            audioFileURL: baseRequest.audioFileURL,
            transcriptionConfiguration: .defaults,
            promptComposition: .init(
                resolvedFreeformPrompt: exactPrompt + "x",
                context: nil,
                emojiCommandsConfiguration: EmojiCommandsConfiguration(isEnabled: false),
                customDictionary: .empty
            )
        )
        await #expect(throws: OpenAITranscriptionRequestBuilderError.self) {
            _ = try await oversizedBuilder.makePreparation(
                oversized,
                cleanupRegistration: oversizedBuilder.makeCleanupRegistration()
            )
        }
        #expect(oversizedFS.createdScratchCount == 0)
    }

    @Test func productionLoopsHandleEINTRShortWritesAndBoundEveryRead() async throws {
        let data = Data((0..<(140 * 1024)).map { UInt8($0 % 251) })
        let source = try temporaryAudio(data: data)
        let scratchDirectory = temporaryDirectory("multipart-posix")
        defer { remove(source.deletingLastPathComponent()); remove(scratchDirectory) }
        let calls = ScriptedPOSIXCalls(
            writeSteps: [.interrupt, .limit(7), .normal],
            syncInterrupts: 1
        )
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-POSIX",
            scratchDirectoryURL: scratchDirectory,
            fileSystem: POSIXOpenAITranscriptionMultipartFileSystem(calls: calls)
        )
        let (preparation, cleanup) = try await prepare(builder, request: try request(source))
        defer { preparation.cleanup(); cleanup.requestCleanup() }
        _ = try await preparation.prepareRequest()

        #expect(calls.readCounts.allSatisfy { $0 <= 64 * 1024 })
        #expect(calls.readCounts.contains(64 * 1024))
        #expect(calls.didUseShortWrite)
        #expect(calls.didRetryInterruptedWrite)
        #expect(calls.didRetryInterruptedSync)
    }

    @Test func zeroProgressWriteFailsAndCleanupRemovesOnlyOwnedScratch() async throws {
        let source = try temporaryAudio(data: Data("audio".utf8))
        let scratchDirectory = temporaryDirectory("multipart-zero")
        defer { remove(source.deletingLastPathComponent()); remove(scratchDirectory) }
        let calls = ScriptedPOSIXCalls(writeSteps: [.zero])
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Zero",
            scratchDirectoryURL: scratchDirectory,
            fileSystem: POSIXOpenAITranscriptionMultipartFileSystem(calls: calls)
        )
        let cleanup = builder.makeCleanupRegistration()
        let preparation = try await builder.makePreparation(
            try request(source),
            cleanupRegistration: cleanup
        )
        await #expect(throws: OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable) {
            _ = try await preparation.prepareRequest()
        }
        preparation.cleanup()
        cleanup.requestCleanup()
        cleanup.requestCleanup()
        #expect(!FileManager.default.fileExists(atPath: preparation.bodyFileURL.path))
        #expect(try Data(contentsOf: source) == Data("audio".utf8))
    }

    @Test func cleanupNeverUnlinksAReplacementAtTheScratchPath() async throws {
        let source = try temporaryAudio(data: Data("audio".utf8))
        let scratchDirectory = temporaryDirectory("multipart-replacement")
        defer {
            remove(source.deletingLastPathComponent())
            remove(scratchDirectory)
        }
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Replacement",
            scratchDirectoryURL: scratchDirectory
        )
        let cleanup = builder.makeCleanupRegistration()
        let preparation = try await builder.makePreparation(
            try request(source),
            cleanupRegistration: cleanup
        )
        let movedOwnedFile = scratchDirectory.appendingPathComponent("moved-owned.multipart")
        try FileManager.default.moveItem(at: preparation.bodyFileURL, to: movedOwnedFile)
        let replacement = Data("replacement-must-survive".utf8)
        try replacement.write(to: preparation.bodyFileURL)

        preparation.cleanup()
        cleanup.requestCleanup()

        #expect(try Data(contentsOf: preparation.bodyFileURL) == replacement)
        #expect(FileManager.default.fileExists(atPath: movedOwnedFile.path))
    }

    @Test func finalizedPinnedDescriptorUploadsOriginalBytesAndPreservesReplacementPath() async throws {
        let sourceData = Data("descriptor-pinned-audio".utf8)
        let source = try temporaryAudio(data: sourceData)
        let scratchDirectory = temporaryDirectory("multipart-pinned-replacement")
        defer {
            remove(source.deletingLastPathComponent())
            remove(scratchDirectory)
        }
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Pinned-Replacement",
            scratchDirectoryURL: scratchDirectory
        )
        let (preparation, cleanup) = try await prepare(builder, request: try request(source))
        let preparedUpload = try await preparation.prepareRequest()
        #expect(!FileManager.default.fileExists(atPath: preparation.bodyFileURL.path))

        let replacement = Data("replacement-path-must-survive".utf8)
        try replacement.write(to: preparation.bodyFileURL)
        let uploadedBody = try readAll(preparedUpload.body)
        preparation.cleanup()
        cleanup.requestCleanup()

        #expect(uploadedBody.contains(sourceData))
        #expect(uploadedBody.contains(replacement) == false)
        #expect(try Data(contentsOf: preparation.bodyFileURL) == replacement)
        #expect(try Data(contentsOf: source) == sourceData)
    }

    @Test func hardLinkedScratchCannotBecomeAnUnlinkedUploadArtifact() async throws {
        let sourceData = Data("hard-link-audio".utf8)
        let source = try temporaryAudio(data: sourceData)
        let scratchDirectory = temporaryDirectory("multipart-hard-link")
        defer {
            remove(source.deletingLastPathComponent())
            remove(scratchDirectory)
        }
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Hard-Link",
            scratchDirectoryURL: scratchDirectory
        )
        let (preparation, cleanup) = try await prepare(builder, request: try request(source))
        defer { preparation.cleanup(); cleanup.requestCleanup() }
        let hardLinkURL = scratchDirectory.appendingPathComponent("retained-hard-link.multipart")
        try FileManager.default.linkItem(at: preparation.bodyFileURL, to: hardLinkURL)

        await #expect(throws: OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable) {
            _ = try await preparation.prepareRequest()
        }

        #expect(FileManager.default.fileExists(atPath: hardLinkURL.path))
        #expect(try Data(contentsOf: source) == sourceData)
    }

    @Test func pinnedArtifactStreamsHaveIndependentFullAndOffsetReads() async throws {
        let sourceData = Data((0..<180_000).map { UInt8($0 % 251) })
        let source = try temporaryAudio(data: sourceData)
        let scratchDirectory = temporaryDirectory("multipart-independent-streams")
        defer {
            remove(source.deletingLastPathComponent())
            remove(scratchDirectory)
        }
        let calls = ScriptedPOSIXCalls(writeSteps: [])
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Independent-Streams",
            scratchDirectoryURL: scratchDirectory,
            fileSystem: POSIXOpenAITranscriptionMultipartFileSystem(calls: calls)
        )
        let (preparation, cleanup) = try await prepare(builder, request: try request(source))
        defer { preparation.cleanup(); cleanup.requestCleanup() }
        let preparedUpload = try await preparation.prepareRequest()
        let artifact = try #require(
            preparedUpload.body as? OpenAITranscriptionMultipartUploadArtifact
        )

        let first = try readAll(artifact)
        let second = try readAll(artifact)
        let offset = Int64(73)
        let offsetStream = try artifact.makeInputStream(
            startingAtOffset: offset,
            failureHandler: { _ in }
        )
        let suffix = try readAll(offsetStream)

        #expect(first == second)
        #expect(suffix == Data(first.dropFirst(Int(offset))))
        #expect(calls.preadCounts.allSatisfy { $0 <= 64 * 1024 })
        #expect(calls.preadOffsets.filter { $0 == 0 }.count >= 2)
        #expect(calls.preadOffsets.contains(offset))
    }

    @Test func concurrentReadsOnOneStreamAdvanceOneSerializedOffset() async throws {
        let sourceData = Data((0..<256).map(UInt8.init))
        let source = try temporaryAudio(data: sourceData)
        let scratchDirectory = temporaryDirectory("multipart-serialized-stream")
        defer {
            remove(source.deletingLastPathComponent())
            remove(scratchDirectory)
        }
        let calls = BlockingFirstPreadCalls()
        defer { calls.release() }
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Serialized-Stream",
            scratchDirectoryURL: scratchDirectory,
            fileSystem: POSIXOpenAITranscriptionMultipartFileSystem(calls: calls)
        )
        let (preparation, cleanup) = try await prepare(builder, request: try request(source))
        defer { preparation.cleanup(); cleanup.requestCleanup() }
        let preparedUpload = try await preparation.prepareRequest()
        let artifact = try #require(
            preparedUpload.body as? OpenAITranscriptionMultipartUploadArtifact
        )
        let harness = ConcurrentStreamReadHarness(
            stream: try #require(
                try artifact.makeInputStream(failureHandler: { _ in })
                    as? OpenAITranscriptionMultipartInputStream
            )
        )
        harness.open()
        defer { harness.close() }

        let first = harness.makeReadTask(count: 10)
        try await calls.waitUntilBlocked()
        let second = harness.makeReadTask(count: 10)
        try await Task.sleep(for: .milliseconds(10))
        #expect(calls.preadInvocationCount == 1)

        calls.release()
        let firstChunk = try await first.value
        let secondChunk = try await second.value
        #expect(firstChunk + secondChunk == Data(try readAll(artifact).prefix(20)))
        #expect(calls.preadOffsets.prefix(2).elementsEqual([0, 10]))
    }

    @Test func closeDuringBlockedPreadReturnsNoBytesAndPreservesClosedState() async throws {
        let source = try temporaryAudio(data: Data("close-during-pread".utf8))
        let scratchDirectory = temporaryDirectory("multipart-close-pread")
        defer {
            remove(source.deletingLastPathComponent())
            remove(scratchDirectory)
        }
        let calls = BlockingFirstPreadCalls()
        defer { calls.release() }
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Close-Pread",
            scratchDirectoryURL: scratchDirectory,
            fileSystem: POSIXOpenAITranscriptionMultipartFileSystem(calls: calls)
        )
        let (preparation, cleanup) = try await prepare(builder, request: try request(source))
        defer { preparation.cleanup(); cleanup.requestCleanup() }
        let preparedUpload = try await preparation.prepareRequest()
        let artifact = try #require(
            preparedUpload.body as? OpenAITranscriptionMultipartUploadArtifact
        )
        let failureCount = LockedInteger()
        let harness = ConcurrentStreamReadHarness(
            stream: try #require(
                try artifact.makeInputStream { _ in failureCount.increment() }
                    as? OpenAITranscriptionMultipartInputStream
            )
        )
        harness.open()
        let read = harness.makeReadTask(count: 10)
        try await calls.waitUntilBlocked()

        harness.close()
        #expect(harness.status == .closed)
        calls.release()

        #expect(try await read.value.isEmpty)
        #expect(harness.status == .closed)
        #expect(failureCount.value == 0)
    }

    @Test func descriptorStreamImplementsExplicitNSStreamStateAndPropertyContract() async throws {
        let source = try temporaryAudio(data: Data("stream-contract".utf8))
        let scratchDirectory = temporaryDirectory("multipart-stream-contract")
        defer {
            remove(source.deletingLastPathComponent())
            remove(scratchDirectory)
        }
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Stream-Contract",
            scratchDirectoryURL: scratchDirectory
        )
        let (preparation, cleanup) = try await prepare(builder, request: try request(source))
        defer { preparation.cleanup(); cleanup.requestCleanup() }
        let preparedUpload = try await preparation.prepareRequest()
        let artifact = try #require(
            preparedUpload.body as? OpenAITranscriptionMultipartUploadArtifact
        )
        let stream = try #require(
            try artifact.makeInputStream(failureHandler: { _ in })
                as? OpenAITranscriptionMultipartInputStream
        )

        #expect(stream.streamStatus == .notOpen)
        #expect(stream.hasBytesAvailable == false)
        #expect(stream.delegate != nil)
        #expect(stream.property(forKey: .fileCurrentOffsetKey) == nil)
        #expect(stream.setProperty(1, forKey: .fileCurrentOffsetKey) == false)
        var bufferPointer: UnsafeMutablePointer<UInt8>?
        var bufferLength = -1
        #expect(stream.getBuffer(&bufferPointer, length: &bufferLength) == false)
        #expect(bufferPointer == nil)
        #expect(bufferLength == 0)
        stream.schedule(in: .main, forMode: .default)
        stream.remove(from: .main, forMode: .default)

        stream.open()
        #expect(stream.streamStatus == .open)
        #expect(stream.hasBytesAvailable)
        _ = try readAll(stream)
        #expect(stream.streamStatus == .closed)
        #expect(stream.hasBytesAvailable == false)
    }

    @Test func earlyEOFAndPreadFailureAreTypedLocalMultipartFailures() async throws {
        for mode in [PreadFailureCalls.Mode.earlyEOF, .failure] {
            let sourceData = Data("local-read-failure-audio".utf8)
            let source = try temporaryAudio(data: sourceData)
            let scratchDirectory = temporaryDirectory("multipart-pread-failure")
            defer {
                remove(source.deletingLastPathComponent())
                remove(scratchDirectory)
            }
            let calls = PreadFailureCalls(mode: mode)
            let builder = OpenAITranscriptionRequestBuilder(
                boundary: "Boundary-Pread-Failure",
                scratchDirectoryURL: scratchDirectory,
                fileSystem: POSIXOpenAITranscriptionMultipartFileSystem(calls: calls)
            )
            let (preparation, cleanup) = try await prepare(builder, request: try request(source))
            defer { preparation.cleanup(); cleanup.requestCleanup() }
            let preparedUpload = try await preparation.prepareRequest()

            #expect(throws: OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable) {
                _ = try readAll(preparedUpload.body)
            }
            #expect(try Data(contentsOf: source) == sourceData)
        }
    }

    @Test func sameSizeMutationThroughPreexistingWriterIsRejectedAfterStreamCreation() async throws {
        let sourceData = Data("immutable-source-audio".utf8)
        let source = try temporaryAudio(data: sourceData)
        let scratchDirectory = temporaryDirectory("multipart-preexisting-writer")
        defer {
            remove(source.deletingLastPathComponent())
            remove(scratchDirectory)
        }
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Preexisting-Writer",
            scratchDirectoryURL: scratchDirectory
        )
        let (preparation, cleanup) = try await prepare(builder, request: try request(source))
        defer { preparation.cleanup(); cleanup.requestCleanup() }
        let writableDescriptor = preparation.bodyFileURL.withUnsafeFileSystemRepresentation {
            path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_WRONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard writableDescriptor >= 0 else {
            throw OpenAITranscriptionMultipartFileSystemError.scratchUnavailable
        }
        defer { Darwin.close(writableDescriptor) }

        let preparedUpload = try await preparation.prepareRequest()
        let artifact = try #require(
            preparedUpload.body as? OpenAITranscriptionMultipartUploadArtifact
        )
        let stream = try artifact.makeInputStream(failureHandler: { _ in })
        try overwriteDescriptor(
            writableDescriptor,
            with: Data(repeating: 0x5a, count: Int(artifact.byteCount))
        )

        #expect(throws: OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable) {
            _ = try readAll(stream)
        }
        #expect(try Data(contentsOf: source) == sourceData)
    }

    @Test func appendTruncateSameSizeOverwriteAndPathReplacementAreRejected() async throws {
        for mutation in SourceMutation.allCases {
            let byteCount = mutation == .truncate ? 80 * 1024 : 1024
            let original = Data(repeating: 65, count: byteCount)
            let source = try temporaryAudio(data: original)
            let scratchDirectory = temporaryDirectory("multipart-mutation")
            defer { remove(source.deletingLastPathComponent()); remove(scratchDirectory) }
            let calls = MutatingPOSIXCalls(mutateAtRead: 2) {
                try mutate(source, kind: mutation, original: original)
            }
            let builder = OpenAITranscriptionRequestBuilder(
                boundary: "Boundary-Mutation",
                scratchDirectoryURL: scratchDirectory,
                fileSystem: POSIXOpenAITranscriptionMultipartFileSystem(calls: calls)
            )
            let cleanup = builder.makeCleanupRegistration()
            let preparation = try await builder.makePreparation(
                try request(source),
                cleanupRegistration: cleanup
            )
            await #expect(throws: OpenAITranscriptionRequestBuilderError.audioFileChanged(source)) {
                _ = try await preparation.prepareRequest()
            }
            preparation.cleanup()
            cleanup.requestCleanup()
        }
    }

    @Test func explicitRetryRebuildsFreshBoundaryAndSettingsWithoutTouchingSource() async throws {
        let audio = Data("same source audio".utf8)
        let source = try temporaryAudio(data: audio)
        let scratchDirectory = temporaryDirectory("multipart-retry")
        defer { remove(source.deletingLastPathComponent()); remove(scratchDirectory) }
        let before = try fileSnapshot(source)
        let builder = OpenAITranscriptionRequestBuilder(scratchDirectoryURL: scratchDirectory)
        let firstConfiguration = TranscriptionConfiguration(
            freeformPrompt: "first-current-setting"
        )
        let secondConfiguration = TranscriptionConfiguration(
            freeformPrompt: "second-current-setting"
        )

        let (first, firstCleanup) = try await prepare(
            builder,
            request: try request(source, transcriptionConfiguration: firstConfiguration)
        )
        let firstUpload = try await first.prepareRequest()
        let firstRequest = firstUpload.request
        let firstBody = try readAll(firstUpload.body)
        first.cleanup()
        firstCleanup.requestCleanup()
        let (second, secondCleanup) = try await prepare(
            builder,
            request: try request(source, transcriptionConfiguration: secondConfiguration)
        )
        let secondUpload = try await second.prepareRequest()
        let secondRequest = secondUpload.request
        let secondBody = try readAll(secondUpload.body)
        second.cleanup()
        secondCleanup.requestCleanup()

        #expect(first.bodyFileURL != second.bodyFileURL)
        #expect(
            firstRequest.value(forHTTPHeaderField: "Content-Type")
                != secondRequest.value(forHTTPHeaderField: "Content-Type")
        )
        #expect(firstBody != secondBody)
        #expect(firstBody.contains(Data("first-current-setting".utf8)))
        #expect(secondBody.contains(Data("second-current-setting".utf8)))
        #expect(try fileSnapshot(source) == before)
        #expect(try Data(contentsOf: source) == audio)
    }

    @Test func cleanupInstallAfterCancellationUnlinksLateScratchAndDiagnosticsAreRedacted() async throws {
        let sourceURL = URL(fileURLWithPath: "/private/source-sentinel.m4a")
        let source = FakeAudioSource(
            identity: testIdentity(byteCount: 4),
            data: Data("KEY!".utf8)
        )
        let scratch = FakeScratchFile(
            fileURL: URL(fileURLWithPath: "/private/scratch-sentinel.multipart")
        )
        let fileSystem = FakeMultipartFileSystem(openResult: .success(source), scratch: scratch)
        let builder = OpenAITranscriptionRequestBuilder(
            boundary: "Boundary-Redacted",
            scratchDirectoryURL: URL(fileURLWithPath: "/private/scratch-sentinel"),
            fileSystem: fileSystem
        )
        let registration = builder.makeCleanupRegistration()
        registration.requestCleanup()
        let preparation = try await builder.makePreparation(
            try request(sourceURL),
            cleanupRegistration: registration
        )
        try await waitUntil { scratch.unlinkCount == 1 }
        let error = OpenAITranscriptionRequestBuilderError.unreadableAudioFile(sourceURL)
        var preparationDump = ""
        dump(preparation, to: &preparationDump)
        var errorDump = ""
        dump(error, to: &errorDump)
        for value in [
            String(reflecting: preparation),
            preparationDump,
            String(reflecting: error),
            errorDump,
        ] {
            #expect(!value.contains("source-sentinel"))
            #expect(!value.contains("scratch-sentinel"))
            #expect(!value.contains("KEY!"))
        }
    }

    @Test func cleanupRequestNeverWaitsForConcurrentCleanupAndRunsExactlyOnce() async throws {
        let registration = OpenAITranscriptionMultipartCleanupRegistration()
        let started = LockedBoolean()
        let release = DispatchSemaphore(value: 0)
        let completionCount = LockedInteger()
        registration.install {
            started.setTrue()
            release.wait()
            completionCount.increment()
        }

        registration.requestCleanup()
        registration.requestCleanup()
        try await waitUntil { started.value }
        #expect(registration.isCleanupCompleted == false)
        #expect(completionCount.value == 0)

        release.signal()
        try await waitUntil { registration.isCleanupCompleted }
        #expect(completionCount.value == 1)
        registration.requestCleanup()
        #expect(completionCount.value == 1)
    }

    private func prepare(
        _ builder: OpenAITranscriptionRequestBuilder,
        request: AudioTranscriptionRequest
    ) async throws -> (
        OpenAITranscriptionMultipartPreparation,
        OpenAITranscriptionMultipartCleanupRegistration
    ) {
        let cleanup = builder.makeCleanupRegistration()
        return (try await builder.makePreparation(request, cleanupRegistration: cleanup), cleanup)
    }

    private func request(
        _ url: URL,
        transcriptionConfiguration: TranscriptionConfiguration = .defaults,
        context: TranscriptionPromptContext? = nil,
        emojiCommandsConfiguration: EmojiCommandsConfiguration = .defaults,
        customDictionary: CustomDictionary = .empty
    ) throws -> AudioTranscriptionRequest {
        try AudioTranscriptionRequest(
            audioFileURL: url,
            transcriptionConfiguration: transcriptionConfiguration,
            promptComposition: TranscriptionPromptComposition(
                resolvedFreeformPrompt: transcriptionConfiguration.resolvedFreeformPrompt,
                context: context,
                emojiCommandsConfiguration: emojiCommandsConfiguration,
                customDictionary: customDictionary
            )
        )
    }
}

nonisolated private enum SourceMutation: CaseIterable, Sendable {
    case append
    case truncate
    case overwrite
    case replacePath
}

nonisolated private func mutate(_ url: URL, kind: SourceMutation, original: Data) throws {
    switch kind {
    case .append:
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([66]))
        try handle.synchronize()
    case .truncate:
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(64 * 1024))
        try handle.synchronize()
    case .overwrite:
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data(repeating: 90, count: original.count))
        try handle.synchronize()
    case .replacePath:
        let moved = url.deletingLastPathComponent()
            .appendingPathComponent("moved-\(UUID().uuidString).m4a")
        try FileManager.default.moveItem(at: url, to: moved)
        try original.write(to: url)
    }
}

private final class FakeMultipartFileSystem:
    OpenAITranscriptionMultipartFileSystem,
    @unchecked Sendable {
    private let lock = NSLock()
    private let openResult: Result<any OpenAITranscriptionAudioSource, Error>
    private let scratch: any OpenAITranscriptionScratchFile
    private var storedOpened = 0
    private var storedCreated = 0

    var openedSourceCount: Int {
        lock.withLock { storedOpened }
    }

    var createdScratchCount: Int {
        lock.withLock { storedCreated }
    }

    init(
        openResult: Result<any OpenAITranscriptionAudioSource, Error>,
        scratch: any OpenAITranscriptionScratchFile = FakeScratchFile()
    ) {
        self.openResult = openResult
        self.scratch = scratch
    }

    func openAudioSource(
        at fileURL: URL
    ) throws -> any OpenAITranscriptionAudioSource {
        lock.withLock { storedOpened += 1 }
        return try openResult.get()
    }

    func createScratchFile(at fileURL: URL) throws -> any OpenAITranscriptionScratchFile {
        lock.withLock { storedCreated += 1 }
        if let scratch = scratch as? FakeScratchFile {
            scratch.setFileURL(fileURL)
        }
        return scratch
    }
}

private final class FakeAudioSource: OpenAITranscriptionAudioSource, @unchecked Sendable {
    let identity: OpenAITranscriptionFileIdentity
    private let lock = NSLock()
    private let data: Data
    private var offset = 0
    private let validationError: Error?

    init(identity: OpenAITranscriptionFileIdentity, data: Data = Data(), validationError: Error? = nil) {
        self.identity = identity
        self.data = data
        self.validationError = validationError
    }

    func read(upToCount count: Int) throws -> Data {
        lock.withLock {
            let end = min(offset + count, data.count)
            defer { offset = end }
            return data[offset..<end]
        }
    }

    func validateUnchanged() throws {
        if let validationError {
            throw validationError
        }
    }

    func close() {}
}

private final class FakeScratchFile: OpenAITranscriptionScratchFile, @unchecked Sendable {
    private let lock = NSLock()
    private var storedURL: URL
    private var body = Data()
    private var unlinks = 0

    var fileURL: URL {
        lock.withLock { storedURL }
    }

    var unlinkCount: Int {
        lock.withLock { unlinks }
    }

    init(fileURL: URL = URL(fileURLWithPath: "/private/fake.multipart")) {
        storedURL = fileURL
    }

    func setFileURL(_ url: URL) {
        lock.withLock { storedURL = url }
    }

    func writeAll(_ data: Data) throws {
        lock.withLock { body.append(data) }
    }

    func synchronizeAndValidate(expectedByteCount: Int64) throws {
        guard lock.withLock({ Int64(body.count) }) == expectedByteCount else {
            throw OpenAITranscriptionMultipartFileSystemError.scratchWriteFailed
        }
    }

    func pinFinalizedUploadArtifact(
        expectedByteCount: Int64
    ) throws -> any OpenAIFileUploadBody {
        let data = lock.withLock { body }
        guard Int64(data.count) == expectedByteCount else {
            throw OpenAITranscriptionMultipartFileSystemError.scratchWriteFailed
        }
        return FakeUploadBody(data: data)
    }

    func close() {}

    func unlinkIfOwned() {
        lock.withLock { unlinks += 1 }
    }
}

private struct FakeUploadBody: OpenAIFileUploadBody, Sendable {
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

private final class ScriptedPOSIXCalls:
    OpenAITranscriptionPOSIXCalling,
    @unchecked Sendable {
    enum WriteStep {
        case interrupt
        case limit(Int)
        case zero
        case normal
    }

    private let lock = NSLock()
    private var steps: [WriteStep]
    private var syncInterrupts: Int
    private var reads: [Int] = []
    private var preads: [(count: Int, offset: Int64)] = []
    private var short = false
    private var interruptedWrite = false
    private var interruptedSync = false

    var readCounts: [Int] {
        lock.withLock { reads }
    }

    var didUseShortWrite: Bool {
        lock.withLock { short }
    }

    var didRetryInterruptedWrite: Bool {
        lock.withLock { interruptedWrite }
    }

    var didRetryInterruptedSync: Bool {
        lock.withLock { interruptedSync }
    }

    var preadCounts: [Int] {
        lock.withLock { preads.map(\.count) }
    }

    var preadOffsets: [Int64] {
        lock.withLock { preads.map(\.offset) }
    }

    init(writeSteps: [WriteStep], syncInterrupts: Int = 0) {
        steps = writeSteps
        self.syncInterrupts = syncInterrupts
    }

    func read(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
        lock.withLock { reads.append(count) }
        return Darwin.read(fd, buffer, count)
    }

    func write(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        let step = lock.withLock { steps.isEmpty ? .normal : steps.removeFirst() }
        switch step {
        case .interrupt:
            lock.withLock { interruptedWrite = true }
            errno = EINTR
            return -1
        case .limit(let limit):
            lock.withLock { short = true }
            return Darwin.write(fd, buffer, min(limit, count))
        case .zero:
            return 0
        case .normal:
            return Darwin.write(fd, buffer, count)
        }
    }

    func synchronize(_ fd: Int32) -> Int32 {
        let interrupt = lock.withLock { () -> Bool in
            guard syncInterrupts > 0 else {
                return false
            }
            syncInterrupts -= 1
            interruptedSync = true
            return true
        }
        if interrupt {
            errno = EINTR
            return -1
        }
        return Darwin.fsync(fd)
    }

    func pread(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int, _ offset: Int64) -> Int {
        lock.withLock { preads.append((count, offset)) }
        return Darwin.pread(fd, buffer, count, off_t(offset))
    }
}

private final class PreadFailureCalls:
    OpenAITranscriptionPOSIXCalling,
    @unchecked Sendable {
    enum Mode {
        case earlyEOF
        case failure
    }

    private let mode: Mode

    init(mode: Mode) {
        self.mode = mode
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
        switch mode {
        case .earlyEOF:
            return 0
        case .failure:
            errno = EIO
            return -1
        }
    }
}

nonisolated private final class BlockingFirstPreadCalls:
    OpenAITranscriptionPOSIXCalling,
    @unchecked Sendable {
    private enum WaitError: Error {
        case didNotBlock
    }

    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didBlock = false
    private var didRelease = false
    private var storedOffsets: [Int64] = []

    var preadInvocationCount: Int {
        lock.withLock { storedOffsets.count }
    }

    var preadOffsets: [Int64] {
        lock.withLock { storedOffsets }
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
            storedOffsets.append(offset)
            guard !didBlock else { return false }
            didBlock = true
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

nonisolated private final class ConcurrentStreamReadHarness: @unchecked Sendable {
    private let stream: OpenAITranscriptionMultipartInputStream

    init(stream: OpenAITranscriptionMultipartInputStream) {
        self.stream = stream
    }

    func open() {
        stream.open()
    }

    func close() {
        stream.close()
    }

    var status: Stream.Status {
        stream.streamStatus
    }

    func makeReadTask(count: Int) -> Task<Data, Error> {
        Task.detached { [stream] in
            try readChunk(stream, count: count)
        }
    }
}

private final class MutatingPOSIXCalls:
    OpenAITranscriptionPOSIXCalling,
    @unchecked Sendable {
    private let lock = NSLock()
    private var readIndex = 0
    private let mutateAtRead: Int
    private let mutation: @Sendable () throws -> Void

    init(
        mutateAtRead: Int,
        mutation: @escaping @Sendable () throws -> Void
    ) {
        self.mutateAtRead = mutateAtRead
        self.mutation = mutation
    }

    func read(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
        let shouldMutate = lock.withLock {
            readIndex += 1
            return readIndex == mutateAtRead
        }
        if shouldMutate {
            do {
                try mutation()
            } catch {
                errno = EIO
                return -1
            }
        }
        return Darwin.read(fd, buffer, count)
    }

    func write(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
        Darwin.write(fd, buffer, count)
    }

    func synchronize(_ fd: Int32) -> Int32 {
        Darwin.fsync(fd)
    }
}

private func testIdentity(byteCount: Int64) -> OpenAITranscriptionFileIdentity {
    .init(
        device: 1,
        inode: 2,
        byteCount: byteCount,
        modificationSeconds: 1,
        modificationNanoseconds: 0,
        changeSeconds: 1,
        changeNanoseconds: 0
    )
}

private func temporaryDirectory(_ prefix: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "holdtype-\(prefix)-\(UUID().uuidString)",
        isDirectory: true
    )
}

private func temporaryAudio(named: String = "recording.m4a", data: Data) throws -> URL {
    let directory = temporaryDirectory("audio")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let url = directory.appendingPathComponent(named)
    try data.write(to: url)
    return url
}

private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func readAll(_ body: any OpenAIFileUploadBody) throws -> Data {
    let stream = try body.makeInputStream { _ in }
    return try readAll(stream)
}

private func readAll(_ stream: InputStream) throws -> Data {
    stream.open()
    defer { stream.close() }

    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else {
            throw stream.streamError ?? OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
        }
        if count == 0 { break }
        result.append(contentsOf: buffer.prefix(count))
    }
    return result
}

nonisolated private func readChunk(
    _ stream: OpenAITranscriptionMultipartInputStream,
    count: Int
) throws -> Data {
    var buffer = [UInt8](repeating: 0, count: count)
    let result = stream.read(&buffer, maxLength: count)
    guard result >= 0 else {
        throw stream.streamError
            ?? OpenAITranscriptionRequestBuilderError.multipartBodyUnavailable
    }
    return Data(buffer.prefix(result))
}

nonisolated private func overwriteDescriptor(_ descriptor: Int32, with data: Data) throws {
    try data.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { return }
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.pwrite(
                descriptor,
                base.advanced(by: offset),
                bytes.count - offset,
                off_t(offset)
            )
            guard count > 0 else {
                throw OpenAITranscriptionMultipartFileSystemError.scratchWriteFailed
            }
            offset += count
        }
    }
    guard Darwin.fchmod(descriptor, 0o400) == 0,
          Darwin.fchmod(descriptor, 0o600) == 0,
          Darwin.fsync(descriptor) == 0 else {
        throw OpenAITranscriptionMultipartFileSystemError.scratchWriteFailed
    }
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @Sendable () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
    while !condition() {
        guard clock.now < deadline else { throw RequestBuilderTestTimeout() }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
}

private struct RequestBuilderTestTimeout: Error {}

nonisolated private final class LockedInteger: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock { storedValue += 1 }
    }
}

nonisolated private final class LockedBoolean: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.withLock { storedValue }
    }

    func setTrue() {
        lock.withLock { storedValue = true }
    }
}

private struct SourceFileSnapshot: Equatable {
    let inode: UInt64
    let byteCount: Int64
    let modificationDate: Date
}

private func fileSnapshot(_ url: URL) throws -> SourceFileSnapshot {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return SourceFileSnapshot(
        inode: try #require((attributes[.systemFileNumber] as? NSNumber)?.uint64Value),
        byteCount: try #require((attributes[.size] as? NSNumber)?.int64Value),
        modificationDate: try #require(attributes[.modificationDate] as? Date)
    )
}
