import Foundation

nonisolated struct KeyboardFixMetadataAction: Codable, Equatable, Sendable {
    let identifier: String
    let kind: KeyboardFixActionKind
    let title: String
    let icon: KeyboardFixIconToken
    let order: Int
    let isEnabled: Bool

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case identifier
        case kind
        case title
        case icon
        case order
        case isEnabled
    }

    init?(
        identifier: String,
        kind: KeyboardFixActionKind,
        title: String,
        icon: KeyboardFixIconToken,
        order: Int,
        isEnabled: Bool
    ) {
        guard KeyboardFixBridgeValidation.isValidIdentifier(identifier),
              kind.rawValue.utf8.count
                <= KeyboardFixBridgeConfiguration.maximumIdentifierUTF8Bytes,
              KeyboardFixBridgeValidation.isValidTitle(title),
              icon.rawValue.utf8.count
                <= KeyboardFixBridgeConfiguration.maximumIconUTF8Bytes,
              (0..<KeyboardFixBridgeConfiguration.maximumActionCount).contains(order)
        else {
            return nil
        }
        self.identifier = identifier
        self.kind = kind
        self.title = title
        self.icon = icon
        self.order = order
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        try KeyboardFixBridgeStrictDecoding.requireExactKeys(
            Set(CodingKeys.allCases.map(\.stringValue)),
            from: decoder
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let action = Self(
            identifier: try container.decode(String.self, forKey: .identifier),
            kind: try container.decode(KeyboardFixActionKind.self, forKey: .kind),
            title: try container.decode(String.self, forKey: .title),
            icon: try container.decode(KeyboardFixIconToken.self, forKey: .icon),
            order: try container.decode(Int.self, forKey: .order),
            isEnabled: try container.decode(Bool.self, forKey: .isEnabled)
        ) else {
            throw KeyboardFixBridgeStrictDecoding.invalidRecord(from: decoder)
        }
        self = action
    }
}

/// App-written, prompt-free projection of the app-private Fix catalog.
nonisolated struct KeyboardFixMetadataSnapshot:
    Codable,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    static let schemaVersion = 1

    let schemaVersion: Int
    let revision: UInt64
    let publishedAt: Date
    let actions: [KeyboardFixMetadataAction]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case revision
        case publishedAt
        case actions
    }

    init?(
        revision: UInt64,
        publishedAt: Date,
        actions: [KeyboardFixMetadataAction]
    ) {
        guard revision > 0,
              publishedAt.timeIntervalSinceReferenceDate.isFinite,
              Self.hasValidActions(actions)
        else {
            return nil
        }
        schemaVersion = Self.schemaVersion
        self.revision = revision
        self.publishedAt = publishedAt
        self.actions = actions
    }

    func action(identifier: String) -> KeyboardFixMetadataAction? {
        actions.first { $0.identifier == identifier }
    }

    var enabledActions: [KeyboardFixMetadataAction] {
        actions.filter(\.isEnabled)
    }

    var description: String {
        "KeyboardFixMetadataSnapshot(revision: \(revision), actionCount: \(actions.count))"
    }

    var debugDescription: String {
        description
    }

    var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "schemaVersion": schemaVersion,
                "revision": revision,
                "publishedAt": publishedAt,
                "actionIdentifiers": actions.map(\.identifier),
            ]
        )
    }

    init(from decoder: Decoder) throws {
        try KeyboardFixBridgeStrictDecoding.requireExactKeys(
            Set(CodingKeys.allCases.map(\.stringValue)),
            from: decoder
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.schemaVersion,
              let snapshot = Self(
                revision: try container.decode(UInt64.self, forKey: .revision),
                publishedAt: try container.decode(Date.self, forKey: .publishedAt),
                actions: try container.decode(
                    [KeyboardFixMetadataAction].self,
                    forKey: .actions
                )
              )
        else {
            throw KeyboardFixBridgeStrictDecoding.invalidRecord(from: decoder)
        }
        self = snapshot
    }

    private static func hasValidActions(
        _ actions: [KeyboardFixMetadataAction]
    ) -> Bool {
        guard (2...KeyboardFixBridgeConfiguration.maximumActionCount)
            .contains(actions.count),
              actions.enumerated().allSatisfy({ $0.element.order == $0.offset }),
              Set(actions.map(\.identifier)).count == actions.count,
              actions[0].identifier
                == KeyboardFixBridgeConfiguration.translateIdentifier,
              actions[0].kind == .translate,
              actions[0].title == "Translate",
              actions[0].icon == .translate,
              actions[0].isEnabled,
              actions[1].identifier == KeyboardFixBridgeConfiguration.fixIdentifier,
              actions[1].kind == .fix,
              actions[1].title == "Fix",
              actions[1].icon == .fix,
              actions[1].isEnabled
        else {
            return false
        }
        return actions.dropFirst(2).allSatisfy {
            $0.kind == .customPrompt
                && $0.identifier
                    != KeyboardFixBridgeConfiguration.translateIdentifier
                && $0.identifier != KeyboardFixBridgeConfiguration.fixIdentifier
        }
    }
}
