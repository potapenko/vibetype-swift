import HoldTypeDomain
import SwiftUI

struct IOSTextFixEditorBuiltInDetailView: View {
    let action: TextFixAction

    var body: some View {
        Form {
            Section("Built-in Fix") {
                LabeledContent("Title", value: action.title)
                LabeledContent(
                    "Icon",
                    value:
                        IOSTextFixEditorIconPresentation.title(
                            for: action.icon
                        )
                )
                LabeledContent("Status", value: "Always enabled")
            }

            Section {
                Text(description)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label(
                    "Built-in Fixes stay first and cannot be edited, "
                        + "disabled, reordered, or deleted.",
                    systemImage: "lock.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(action.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.fixes.editor.builtin-detail")
    }

    private var description: String {
        switch action.kind {
        case .translate:
            "Uses your saved HoldType Translation route and model."
        case .fix:
            "Uses your saved Writing & Correction model and prompt for "
                + "this request without changing automatic correction."
        case .customPrompt:
            ""
        }
    }
}

#Preview("Built-in Fix detail") {
    NavigationStack {
        IOSTextFixEditorBuiltInDetailView(
            action: TextFixCatalog.defaults.actions[0]
        )
    }
}
