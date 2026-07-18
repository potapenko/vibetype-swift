//
//  TranscriptHistoryEntry.swift
//  HoldType
//
//  Created by Codex on 6/20/26.
//

import Foundation

struct TranscriptHistoryEntry: Codable, Equatable, Identifiable {
    enum ValidationError: Error, Equatable {
        case emptyTranscriptText
    }

    let id: UUID
    let createdAt: Date
    let transcriptText: String
    let transcriptionModel: String
    let languageCode: String?
    let audioDuration: TimeInterval?
    let cachedAudioFileURL: URL?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        transcriptText: String,
        transcriptionModel: String,
        languageCode: String?,
        audioDuration: TimeInterval? = nil,
        cachedAudioFileURL: URL? = nil
    ) throws {
        let normalizedTranscriptText = transcriptText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTranscriptText.isEmpty else {
            throw ValidationError.emptyTranscriptText
        }

        self.id = id
        self.createdAt = createdAt
        self.transcriptText = normalizedTranscriptText
        self.transcriptionModel = transcriptionModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.languageCode = languageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        self.audioDuration = audioDuration
        self.cachedAudioFileURL = cachedAudioFileURL
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case transcriptText
        case transcriptionModel
        case languageCode
        case audioDuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        transcriptText = try container.decode(String.self, forKey: .transcriptText)
        transcriptionModel = try container.decode(String.self, forKey: .transcriptionModel)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        audioDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .audioDuration)
        cachedAudioFileURL = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(transcriptText, forKey: .transcriptText)
        try container.encode(transcriptionModel, forKey: .transcriptionModel)
        try container.encodeIfPresent(languageCode, forKey: .languageCode)
        try container.encodeIfPresent(audioDuration, forKey: .audioDuration)
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
