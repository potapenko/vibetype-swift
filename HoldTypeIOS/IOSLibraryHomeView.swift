import HoldTypeDomain
import HoldTypePersistence
import SwiftUI

struct IOSLibraryHomeView: View {
    @Environment(IOSLibraryStateOwner.self) private var stateOwner
    @State private var isLoading = false

    var body: some View {
        Group {
            switch stateOwner.state {
            case .notLoaded:
                IOSDestinationLoadingView(title: "Loading Library")
            case .loadFailed:
                IOSDestinationLoadFailureView(
                    title: "Library Unavailable",
                    description:
                        "HoldType couldn’t read your Library. No empty "
                        + "replacement was created.",
                    isRetrying: isLoading,
                    retry: retryLoad
                )
            case .ready(let content):
                IOSLibrarySummaryList(
                    content: content,
                    showsSaveFailure: false
                )
            case .saveFailed(let lastDurableValue):
                IOSLibrarySummaryList(
                    content: lastDurableValue,
                    showsSaveFailure: true
                )
            }
        }
        .navigationTitle("Library")
        .accessibilityIdentifier(
            IOSContainingAppDestination.library.accessibilityIdentifier
        )
        .task {
            guard case .notLoaded = stateOwner.state else { return }
            await load()
        }
    }

    private func retryLoad() {
        Task { await load() }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        _ = try? await stateOwner.load()
    }
}

private struct IOSLibrarySummaryList: View {
    let content: IOSLibraryContent
    let showsSaveFailure: Bool

    var body: some View {
        List {
            if showsSaveFailure {
                IOSSaveFailureSection(subject: "Library")
            }

            Section("Saved Content") {
                LabeledContent(
                    "Dictionary",
                    value: countLabel(
                        content.customDictionary.entries.count,
                        singular: "entry",
                        plural: "entries"
                    )
                )
                LabeledContent(
                    "Custom emoji commands",
                    value: countLabel(
                        content.emojiCommandsConfiguration.customCommands.count,
                        singular: "command",
                        plural: "commands"
                    )
                )
                LabeledContent(
                    "Replacement rules",
                    value: countLabel(
                        content.replacementRules.count,
                        singular: "rule",
                        plural: "rules"
                    )
                )
            }

            Section("Saved Emoji Preference") {
                LabeledContent(
                    "Emoji commands",
                    value: content.emojiCommandsConfiguration.isEnabled
                        ? "Preference on"
                        : "Preference off"
                )
                LabeledContent(
                    "Selected built-in set",
                    value: builtInEmojiSetName(
                        content.emojiCommandsConfiguration
                            .enabledBuiltInSetIDs.first
                    )
                )
            }

            Section {
                Text(
                    "Library content stays in HoldType’s private storage. It "
                    + "is not copied into the keyboard extension or App Group."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func countLabel(
        _ count: Int,
        singular: String,
        plural: String
    ) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    private func builtInEmojiSetName(_ identifier: String?) -> String {
        switch identifier {
        case "en":
            "English"
        case "ru":
            "Russian"
        case "es":
            "Spanish"
        case "de":
            "German"
        case "fr":
            "French"
        case "pt":
            "Portuguese"
        case nil:
            "None"
        default:
            "Unknown"
        }
    }
}
