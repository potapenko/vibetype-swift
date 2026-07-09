import Foundation

public struct AcceptedTranscript: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case emptyText
    }

    public let text: String

    public init(rawText: String) throws {
        guard let normalizedText = Self.nonEmptyNormalizedText(from: rawText) else {
            throw ValidationError.emptyText
        }

        self.text = normalizedText
    }

    public static func nonEmptyNormalizedText(from rawText: String) -> String? {
        let normalizedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedText.isEmpty ? nil : normalizedText
    }
}
