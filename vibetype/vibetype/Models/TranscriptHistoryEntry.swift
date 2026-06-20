//
//  TranscriptHistoryEntry.swift
//  vibetype
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

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        transcriptText: String,
        transcriptionModel: String,
        languageCode: String?,
        audioDuration: TimeInterval? = nil
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
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
