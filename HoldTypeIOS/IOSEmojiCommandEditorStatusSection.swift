import SwiftUI

struct IOSEmojiCommandEditorStatusSection: View {
    let phase: IOSEmojiCommandEditorPhase
    let canReloadLatest: Bool
    let canReplaceLatest: Bool
    let reloadLatest: () -> Void
    let requestReplaceLatest: () -> Void

    @ViewBuilder
    var body: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .saving:
            Section {
                ProgressView("Saving…")
            }
        case .saved:
            Section {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        case .saveFailed:
            Section {
                IOSSettingsWarningLabel(
                    "Not Saved. The saved command is unchanged and any draft is retained.",
                    color: .red
                )
            }
        case .changedElsewhere:
            Section("Changed Elsewhere") {
                IOSSettingsWarningLabel(
                    "The saved command changed. This draft has not been saved.",
                    color: .orange
                )
                Button("Reload Latest", action: reloadLatest)
                    .disabled(!canReloadLatest)
                Button("Replace Latest", role: .destructive) {
                    requestReplaceLatest()
                }
                .disabled(!canReplaceLatest)
            }
        case .deletedElsewhere:
            Section {
                IOSSettingsWarningLabel(
                    "This command was deleted elsewhere. Save cannot recreate it.",
                    color: .orange
                )
            }
        case .invalid:
            Section {
                IOSSettingsWarningLabel(
                    "This draft is invalid or conflicts with another custom phrase.",
                    color: .red
                )
            }
        }
    }
}

#Preview("Custom emoji command — changed elsewhere") {
    Form {
        IOSEmojiCommandEditorStatusSection(
            phase: .changedElsewhere,
            canReloadLatest: true,
            canReplaceLatest: true,
            reloadLatest: {},
            requestReplaceLatest: {}
        )
    }
}
