import Foundation
import HoldTypeDomain

nonisolated enum IOSTextFixEditorPhase: Equatable, Sendable {
    case notLoaded
    case loading
    case ready
    case saving
}
nonisolated enum IOSTextFixEditorMutationError: Equatable, Sendable {
    case catalogNotLoaded
    case operationInFlight
    case builtInReadOnly
    case actionNotFound
    case anotherDraftIsOpen
    case invalidMove
    case invalidDraft(IOSTextFixEditorDraftValidation)
    case catalogRejectedChange
}

nonisolated enum IOSTextFixEditorFailure: Equatable, Sendable {
    case loadFailed
    case saveFailed
    case changeRejected(IOSTextFixEditorMutationError)
}

nonisolated enum IOSTextFixEditorDraftValidation: Equatable, Sendable {
    case valid
    case missingTitle
    case titleTooLong(maximumCharacterCount: Int)
    case missingPrompt
    case promptTooLarge(maximumUTF8ByteCount: Int)
}

nonisolated struct IOSTextFixEditorDraft:
    Equatable,
    Identifiable,
    Sendable
{
    let id: String
    var title: String
    var prompt: String
    var icon: TextFixIcon
    var isEnabled: Bool

    init(
        id: String,
        title: String = "",
        prompt: String = "",
        icon: TextFixIcon = .custom,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.icon = icon
        self.isEnabled = isEnabled
    }

    init(customAction action: TextFixAction) {
        id = action.id
        title = action.title
        prompt = action.prompt ?? ""
        icon = action.icon
        isEnabled = action.isEnabled
    }

    static func newIdentifier(uuid: UUID = UUID()) -> String {
        "custom.\(uuid.uuidString.lowercased())"
    }

    var validation: IOSTextFixEditorDraftValidation {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .missingTitle
        }
        guard title.count <= TextFixAction.maximumTitleCharacterCount else {
            return .titleTooLong(
                maximumCharacterCount:
                    TextFixAction.maximumTitleCharacterCount
            )
        }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .missingPrompt
        }
        guard prompt.utf8.count <= TextFixAction.maximumPromptUTF8ByteCount
        else {
            return .promptTooLarge(
                maximumUTF8ByteCount:
                    TextFixAction.maximumPromptUTF8ByteCount
            )
        }
        return .valid
    }

    var hasMeaningfulInput: Bool {
        !title.isEmpty
            || !prompt.isEmpty
            || icon != .custom
            || !isEnabled
    }

    func action() throws -> TextFixAction {
        try TextFixAction(
            id: id,
            kind: .customPrompt,
            title: title,
            icon: icon,
            prompt: prompt,
            isEnabled: isEnabled
        )
    }
}

nonisolated enum IOSTextFixEditorRoute: Hashable, Sendable {
    case builtIn(String)
    case custom(String)
    case newCustom(String)

    var identifier: String {
        switch self {
        case .builtIn(let identifier),
             .custom(let identifier),
             .newCustom(let identifier):
            identifier
        }
    }
}

extension IOSTextFixEditorDraft: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSTextFixEditorDraft(id: \(id), content: <redacted>)"
    }

    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "id": id,
                "titleCharacterCount": title.count,
                "prompt": "<redacted>",
                "icon": icon.rawValue,
                "isEnabled": isEnabled,
            ]
        )
    }
}

extension IOSTextFixEditorRoute: CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable {
    var description: String {
        "IOSTextFixEditorRoute(identifier: \(identifier))"
    }

    var debugDescription: String { description }

    var customMirror: Mirror {
        Mirror(self, children: ["identifier": identifier])
    }
}
