import Foundation
import HoldTypeDomain
import SwiftUI

struct IOSEmojiCommandEditorForm: View {
    let isNew: Bool
    let session: IOSEmojiCommandEditorSession
    let customCommands: [CustomEmojiCommand]
    @Binding var output: String
    @Binding var primaryPhrase: String
    @Binding var aliasesText: String
    let canDelete: Bool
    let isDisabled: Bool
    let reloadLatest: () -> Void
    let requestReplaceLatest: () -> Void
    let requestDelete: () -> Void

    var body: some View {
        Form {
            IOSEmojiCommandEditorStatusSection(
                phase: session.phase,
                canReloadLatest: session.canReloadLatest,
                canReplaceLatest: session.canReplaceLatest
                    && session.validation(in: customCommands) == .valid,
                reloadLatest: reloadLatest,
                requestReplaceLatest: requestReplaceLatest
            )

            Section("Command") {
                TextField(
                    "Output",
                    text: $output,
                    axis: .vertical
                )
                .lineLimit(1...3)
                .autocorrectionDisabled()
                .accessibilityHint(
                    "Enter the text or emoji produced by the spoken phrase."
                )

                TextField(
                    "Primary spoken phrase",
                    text: $primaryPhrase,
                    axis: .vertical
                )
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Section("Aliases") {
                TextField(
                    "One optional alias per line",
                    text: $aliasesText,
                    axis: .vertical
                )
                .lineLimit(3...10)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Text(
                    "Aliases are alternate spoken phrases for the same output."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            validationSection

            if !isNew {
                Section {
                    Button(
                        "Delete Custom Command",
                        role: .destructive,
                        action: requestDelete
                    )
                    .disabled(!canDelete)
                }
            }

            Section {
                Text(
                    "Custom commands are normalized only when you Save. "
                        + "They remain private to the containing app and are "
                        + "never copied into the keyboard extension."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .disabled(isDisabled)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var validationSection: some View {
        if session.isDirty {
            switch session.validation(in: customCommands) {
            case .valid:
                EmptyView()
            case .missingOutput:
                Section {
                    IOSSettingsWarningLabel(
                        "Enter a non-empty output.",
                        color: .red
                    )
                }
            case .missingPrimaryPhrase:
                Section {
                    IOSSettingsWarningLabel(
                        "Enter a primary spoken phrase. An alias cannot replace it.",
                        color: .red
                    )
                }
            case .customPhraseCollision:
                Section {
                    IOSSettingsWarningLabel(
                        "A primary phrase or alias already belongs to another custom command.",
                        color: .red
                    )
                }
            }
        }
    }
}

extension IOSEmojiCommandEditorForm: CustomReflectable {
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

#Preview("Custom emoji command editor form") {
    let command = CustomEmojiCommand(
        id: UUID(
            uuid: (0x20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)
        ),
        emoji: "🚀",
        command: "emoji launch",
        aliases: ["emoji rocket"]
    )

    NavigationStack {
        IOSEmojiCommandEditorForm(
            isNew: false,
            session: IOSEmojiCommandEditorSession(command: command),
            customCommands: [command],
            output: .constant(command.emoji),
            primaryPhrase: .constant(command.command),
            aliasesText: .constant(command.aliases.joined(separator: "\n")),
            canDelete: true,
            isDisabled: false,
            reloadLatest: {},
            requestReplaceLatest: {},
            requestDelete: {}
        )
        .navigationTitle("Custom Command")
    }
}
