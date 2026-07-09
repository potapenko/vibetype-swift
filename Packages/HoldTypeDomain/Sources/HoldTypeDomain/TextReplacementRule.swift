import Foundation

public struct TextReplacementRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var search: String
    public var replacement: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        search: String,
        replacement: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.search = search
        self.replacement = replacement
        self.isEnabled = isEnabled
    }

    public var hasSearchText: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case search
        case replacement
        case isEnabled
    }
}
