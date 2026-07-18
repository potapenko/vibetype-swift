import SwiftUI

struct IOSSettingsEditorStatusSection: View {
    let phase: IOSSettingsEditorPhase
    var retry: () -> Void = {}
    var useSavedValue: () -> Void = {}

    @ViewBuilder
    var body: some View {
        switch phase {
        case .idle, .pending, .saved:
            EmptyView()
        case .saving:
            Section {
                ProgressView("Saving…")
                    .accessibilityIdentifier("ios.settings.editor.saving")
            }
        case .validationBlocked:
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Changes Not Applied")
                            .font(.headline)
                        Text("Fix the highlighted value to save automatically.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
                .accessibilityIdentifier(
                    "ios.settings.editor.validation-blocked"
                )
            }
        case .saveFailed:
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not Saved")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(
                            "Your changes are still here. Try again or use the saved value."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                .accessibilityIdentifier(
                    "ios.settings.editor.save-failed"
                )

                Button("Try Again", action: retry)
                Button("Use Saved Value", action: useSavedValue)
            }
        case .changedElsewhere:
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings Changed Elsewhere")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(
                            "Choose whether to apply your changes or use the newer saved value."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                }
                .accessibilityIdentifier(
                    "ios.settings.editor.changed-elsewhere"
                )

                Button("Try Again", action: retry)
                Button("Use Saved Value", action: useSavedValue)
            }
        }
    }
}

#Preview("Settings editor — Save failed") {
    Form {
        IOSSettingsEditorStatusSection(phase: .saveFailed)
    }
}
