//
//  AcceptedTranscript.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import Foundation

struct AcceptedTranscript: Equatable {
    enum ValidationError: Error, Equatable {
        case emptyText
    }

    let text: String

    init(rawText: String) throws {
        guard let normalizedText = Self.nonEmptyNormalizedText(from: rawText) else {
            throw ValidationError.emptyText
        }

        self.text = normalizedText
    }

    static func nonEmptyNormalizedText(from rawText: String) -> String? {
        let normalizedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedText.isEmpty ? nil : normalizedText
    }
}
