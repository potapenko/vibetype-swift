import HoldTypeDomain
import SwiftUI

struct IOSTextFixEditorCustomRow: View {
    let action: TextFixAction
    let position: Int
    let totalCount: Int
    let isDisabled: Bool
    let onSetEnabled: (Bool) -> Void
    let onRequestDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(
                "Enable \(action.title)",
                isOn: Binding(
                    get: { action.isEnabled },
                    set: onSetEnabled
                )
            )
            .labelsHidden()
            .disabled(isDisabled)

            NavigationLink(
                value: IOSTextFixEditorRoute.custom(action.id)
            ) {
                HStack(alignment: .top, spacing: 12) {
                    actionIcon
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(action.isEnabled ? "Enabled" : "Off")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(isDisabled)
            .accessibilityValue(
                "Position \(position + 1) of \(totalCount)"
            )
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) {
                onRequestDelete()
            }
            .disabled(isDisabled)
        }
        .contextMenu {
            Button("Delete Fix", role: .destructive) {
                onRequestDelete()
            }
            .disabled(isDisabled)
        }
        .accessibilityIdentifier("ios.fixes.custom.\(action.id)")
    }

    private var actionIcon: some View {
        Image(
            systemName:
                IOSTextFixEditorIconPresentation.systemImage(
                    for: action.icon
                )
        )
        .font(.title3)
        .foregroundStyle(
            action.isEnabled ? Color.accentColor : Color.secondary
        )
        .frame(width: 28)
        .accessibilityHidden(true)
    }
}

extension IOSTextFixEditorCustomRow: CustomReflectable {
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

#Preview("Custom Fix row") {
    NavigationStack {
        List {
            IOSTextFixEditorCustomRow(
                action: TextFixCatalog.defaults.customActions[0],
                position: 0,
                totalCount: TextFixCatalog.defaults.customActions.count,
                isDisabled: false,
                onSetEnabled: { _ in },
                onRequestDelete: {}
            )
        }
    }
}
