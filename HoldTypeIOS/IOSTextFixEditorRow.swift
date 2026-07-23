import HoldTypeDomain
import SwiftUI

struct IOSTextFixEditorBuiltInRow: View {
    let action: TextFixAction

    var body: some View {
        NavigationLink(
            value: IOSTextFixEditorRoute.builtIn(action.id)
        ) {
            HStack(spacing: 12) {
                actionIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title)
                        .font(.body.weight(.medium))
                    Text("Built in · Always available")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier(
            "ios.fixes.builtin.\(action.id)"
        )
    }

    private var actionIcon: some View {
        Image(
            systemName:
                IOSTextFixEditorIconPresentation.systemImage(
                    for: action.icon
                )
        )
        .font(.title3)
        .foregroundStyle(.tint)
        .frame(width: 28)
        .accessibilityHidden(true)
    }
}

extension IOSTextFixEditorBuiltInRow: CustomReflectable {
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

#Preview("Built-in Fix row") {
    NavigationStack {
        List {
            IOSTextFixEditorBuiltInRow(
                action: TextFixCatalog.defaults.actions[0]
            )
        }
    }
}
