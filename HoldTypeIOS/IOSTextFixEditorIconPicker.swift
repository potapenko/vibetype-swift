import HoldTypeDomain
import SwiftUI

enum IOSTextFixEditorIconPresentation {
    static func title(for icon: TextFixIcon) -> String {
        switch icon {
        case .translate: "Translate"
        case .fix: "Fix"
        case .improveWriting: "Improve Writing"
        case .makeShorter: "Make Shorter"
        case .summarize: "Summarize"
        case .bulletPoints: "Bullet Points"
        case .casual: "Casual"
        case .markdown: "Markdown"
        case .formal: "Formal"
        case .expand: "Expand"
        case .rewrite: "Rewrite"
        case .custom: "Sparkles"
        }
    }

    static func systemImage(for icon: TextFixIcon) -> String {
        switch icon {
        case .translate: "character.book.closed"
        case .fix: "text.badge.checkmark"
        case .improveWriting: "wand.and.stars"
        case .makeShorter: "decrease.indent"
        case .summarize: "bolt"
        case .bulletPoints: "list.bullet"
        case .casual: "face.smiling"
        case .markdown: "text.document"
        case .formal: "briefcase"
        case .expand: "arrow.up.left.and.arrow.down.right"
        case .rewrite: "arrow.triangle.2.circlepath"
        case .custom: "sparkles"
        }
    }
}
struct IOSTextFixEditorIconPicker: View {
    @Binding var icon: TextFixIcon

    var body: some View {
        Picker("Icon", selection: rawValueBinding) {
            ForEach(TextFixIcon.allCases, id: \.rawValue) { option in
                Label(
                    IOSTextFixEditorIconPresentation.title(for: option),
                    systemImage:
                        IOSTextFixEditorIconPresentation.systemImage(
                            for: option
                        )
                )
                .tag(option.rawValue)
            }
        }
        .accessibilityIdentifier("ios.fixes.editor.icon")
    }

    private var rawValueBinding: Binding<String> {
        Binding(
            get: { icon.rawValue },
            set: { rawValue in
                guard let selected = TextFixIcon(
                    rawValue: rawValue
                ) else { return }
                icon = selected
            }
        )
    }
}

#Preview("Fix icon picker") {
    Form {
        IOSTextFixEditorIconPicker(icon: .constant(.improveWriting))
    }
}
