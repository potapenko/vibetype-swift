import HoldTypeDomain
import SwiftUI

struct IOSBuiltInEmojiCommandDetailView: View {
    let reference: IOSBuiltInEmojiCommandReference

    var body: some View {
        let command = reference.command
        Form {
            Section("Output") {
                Text(command.emoji)
                    .font(.largeTitle)
                    .accessibilityLabel("Output \(command.emoji)")
            }

            Section("Primary Spoken Phrase") {
                Text(command.primarySpokenPhrase)
                    .textSelection(.enabled)
            }

            if !command.secondarySpokenPhrases.isEmpty {
                Section("Aliases") {
                    ForEach(
                        command.secondarySpokenPhrases,
                        id: \.self
                    ) { alias in
                        Text(alias)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                Text(
                    "This bundled command is used locally after "
                        + "transcription when its language set is active."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(command.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(
            "ios.library.emoji-commands.built-in-detail.screen"
        )
    }
}

extension IOSBuiltInEmojiCommandDetailView: CustomReflectable {
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

#Preview("Built-in emoji command") {
    NavigationStack {
        if let reference = IOSBuiltInEmojiCommandReference(
            setID: "en",
            commandID: "smile"
        ) {
            IOSBuiltInEmojiCommandDetailView(reference: reference)
        }
    }
}
