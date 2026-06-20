//
//  OpenAITranscriptionRequestBuilder.swift
//  vibetype
//
//  Created by Codex on 6/20/26.
//

import Foundation

struct OpenAITranscriptionRequestBuilder {
    static let defaultEndpointURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

    private let endpointURL: URL
    private let boundary: String
    private let fileManager: FileManager

    init(
        endpointURL: URL = Self.defaultEndpointURL,
        boundary: String = "Boundary-\(UUID().uuidString)",
        fileManager: FileManager = .default
    ) {
        self.endpointURL = endpointURL
        self.boundary = boundary
        self.fileManager = fileManager
    }

    func makeRequest(audioFileURL: URL, settings: AppSettings) throws -> URLRequest {
        let audioFile = try validatedAudioFile(at: audioFileURL)
        let body = makeMultipartBody(audioFile: audioFile, settings: settings)

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = body
        return request
    }

    private func validatedAudioFile(at audioFileURL: URL) throws -> AudioFilePart {
        let path = audioFileURL.path
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw OpenAITranscriptionRequestBuilderError.missingAudioFile(audioFileURL)
        }

        let fileExtension = audioFileURL.pathExtension.lowercased()
        guard let contentType = Self.supportedContentTypeByExtension[fileExtension] else {
            throw OpenAITranscriptionRequestBuilderError.unsupportedAudioFileType(fileExtension)
        }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            let fileSize = attributes[.size] as? NSNumber
            guard let fileSize, fileSize.int64Value > 0 else {
                throw OpenAITranscriptionRequestBuilderError.emptyAudioFile(audioFileURL)
            }
        } catch let error as OpenAITranscriptionRequestBuilderError {
            throw error
        } catch {
            throw OpenAITranscriptionRequestBuilderError.unreadableAudioFile(audioFileURL)
        }

        do {
            let data = try Data(contentsOf: audioFileURL)
            guard !data.isEmpty else {
                throw OpenAITranscriptionRequestBuilderError.emptyAudioFile(audioFileURL)
            }

            return AudioFilePart(
                fileName: audioFileURL.lastPathComponent,
                contentType: contentType,
                data: data
            )
        } catch let error as OpenAITranscriptionRequestBuilderError {
            throw error
        } catch {
            throw OpenAITranscriptionRequestBuilderError.unreadableAudioFile(audioFileURL)
        }
    }

    private func makeMultipartBody(audioFile: AudioFilePart, settings: AppSettings) -> Data {
        var body = Data()

        body.appendFormField(name: "model", value: settings.resolvedTranscriptionModel, boundary: boundary)
        body.appendFormField(name: "response_format", value: "json", boundary: boundary)

        if let languageCode = settings.resolvedLanguageCode {
            body.appendFormField(name: "language", value: languageCode, boundary: boundary)
        }

        if let prompt = settings.resolvedPrompt {
            body.appendFormField(name: "prompt", value: prompt, boundary: boundary)
        }

        body.appendFileField(
            name: "file",
            fileName: audioFile.fileName,
            contentType: audioFile.contentType,
            data: audioFile.data,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")

        return body
    }

    private static let supportedContentTypeByExtension = [
        "m4a": "audio/mp4",
        "wav": "audio/wav",
    ]
}

enum OpenAITranscriptionRequestBuilderError: Error, Equatable, LocalizedError {
    case missingAudioFile(URL)
    case emptyAudioFile(URL)
    case unsupportedAudioFileType(String)
    case unreadableAudioFile(URL)

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            return "The recording file is missing."
        case .emptyAudioFile:
            return "The recording file is empty."
        case .unsupportedAudioFileType:
            return "The recording format is not supported."
        case .unreadableAudioFile:
            return "The recording file could not be read."
        }
    }
}

private struct AudioFilePart {
    let fileName: String
    let contentType: String
    let data: Data
}

private extension Data {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendFileField(
        name: String,
        fileName: String,
        contentType: String,
        data: Data,
        boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n"
        )
        appendString("Content-Type: \(contentType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }

    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
