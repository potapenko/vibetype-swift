//
//  OpenAITranscriptionRequestBuilderTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/20/26.
//

import Foundation
import Testing
@testable import vibetype

struct OpenAITranscriptionRequestBuilderTests {

    @Test func buildsMultipartRequestWithConfiguredSettingsAndAudioFile() throws {
        let audioFileURL = try makeTemporaryAudioFile(
            named: "recording.m4a",
            contents: Data("fake audio bytes".utf8)
        )
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        var settings = AppSettings.defaults
        settings.transcriptionModel = "custom-transcribe-model"
        settings.language = .english
        settings.prompt = "  product names, Swift symbols  "

        let request = try OpenAITranscriptionRequestBuilder(boundary: "Boundary-Test")
            .makeRequest(audioFileURL: audioFileURL, settings: settings)

        #expect(request.url == OpenAITranscriptionRequestBuilder.defaultEndpointURL)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")
                == "multipart/form-data; boundary=Boundary-Test"
        )

        let body = try #require(request.httpBody)
        let bodyText = try #require(String(data: body, encoding: .utf8))

        #expect(bodyText.contains("Content-Disposition: form-data; name=\"model\""))
        #expect(bodyText.contains("custom-transcribe-model"))
        #expect(bodyText.contains("Content-Disposition: form-data; name=\"response_format\""))
        #expect(bodyText.contains("json"))
        #expect(bodyText.contains("Content-Disposition: form-data; name=\"language\""))
        #expect(bodyText.contains("\r\n\r\nen\r\n"))
        #expect(bodyText.contains("Content-Disposition: form-data; name=\"prompt\""))
        #expect(bodyText.contains("\r\n\r\nproduct names, Swift symbols\r\n"))
        #expect(
            bodyText.contains(
                "Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\""
            )
        )
        #expect(bodyText.contains("Content-Type: audio/mp4"))
        #expect(bodyText.contains("fake audio bytes"))
        #expect(bodyText.hasSuffix("--Boundary-Test--\r\n"))
    }

    @Test func omitsAutomaticLanguageAndBlankPrompt() throws {
        let audioFileURL = try makeTemporaryAudioFile(
            named: "recording.wav",
            contents: Data("wav bytes".utf8)
        )
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        var settings = AppSettings.defaults
        settings.transcriptionModel = "   "
        settings.language = .automatic
        settings.prompt = "   "

        let request = try OpenAITranscriptionRequestBuilder(boundary: "Boundary-Test")
            .makeRequest(audioFileURL: audioFileURL, settings: settings)
        let bodyText = try #require(request.multipartBodyText)

        #expect(bodyText.contains(AppSettings.defaultTranscriptionModel))
        #expect(bodyText.contains("name=\"language\"") == false)
        #expect(bodyText.contains("name=\"prompt\"") == false)
        #expect(bodyText.contains("Content-Type: audio/wav"))
    }

    @Test func throwsControlledErrorForMissingAudioFile() {
        let missingFileURL = URL(fileURLWithPath: "/tmp/vibetype-missing-recording.m4a")
        let builder = OpenAITranscriptionRequestBuilder(boundary: "Boundary-Test")

        #expect(throws: OpenAITranscriptionRequestBuilderError.missingAudioFile(missingFileURL)) {
            _ = try builder.makeRequest(audioFileURL: missingFileURL, settings: .defaults)
        }
    }

    @Test func throwsControlledErrorForEmptyAudioFile() throws {
        let audioFileURL = try makeTemporaryAudioFile(named: "empty.wav", contents: Data())
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let builder = OpenAITranscriptionRequestBuilder(boundary: "Boundary-Test")

        #expect(throws: OpenAITranscriptionRequestBuilderError.emptyAudioFile(audioFileURL)) {
            _ = try builder.makeRequest(audioFileURL: audioFileURL, settings: .defaults)
        }
    }

    @Test func throwsControlledErrorForUnsupportedFileType() throws {
        let audioFileURL = try makeTemporaryAudioFile(
            named: "recording.txt",
            contents: Data("not audio".utf8)
        )
        defer { try? FileManager.default.removeItem(at: audioFileURL.deletingLastPathComponent()) }

        let builder = OpenAITranscriptionRequestBuilder(boundary: "Boundary-Test")

        #expect(throws: OpenAITranscriptionRequestBuilderError.unsupportedAudioFileType("txt")) {
            _ = try builder.makeRequest(audioFileURL: audioFileURL, settings: .defaults)
        }
    }

    private func makeTemporaryAudioFile(named fileName: String, contents: Data) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibetype-request-builder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent(fileName)
        try contents.write(to: fileURL)
        return fileURL
    }
}

private extension URLRequest {
    var multipartBodyText: String? {
        guard let httpBody else {
            return nil
        }

        return String(data: httpBody, encoding: .utf8)
    }
}
