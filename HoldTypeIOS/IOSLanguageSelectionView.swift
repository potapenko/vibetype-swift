import HoldTypeDomain
import SwiftUI

enum IOSLanguageSelectionPresentation {
    nonisolated static func title(
        for language: TranscriptionLanguage,
        automaticTitle: String
    ) -> String {
        language == .automatic
            ? automaticTitle
            : language.iosSettingsDisplayName
    }

    nonisolated static func matches(
        _ language: TranscriptionLanguage,
        automaticTitle: String,
        query: String
    ) -> Bool {
        let trimmed = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return true }
        let title = title(
            for: language,
            automaticTitle: automaticTitle
        )
        return title.localizedCaseInsensitiveContains(trimmed)
            || language.rawValue.localizedCaseInsensitiveContains(trimmed)
            || (language.languageCode?
                .localizedCaseInsensitiveContains(trimmed) ?? false)
    }
}

struct IOSLanguageSelectionView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [TranscriptionLanguage]
    let automaticTitle: String
    @Binding var selection: TranscriptionLanguage
    @State private var query = ""

    var body: some View {
        List(filteredOptions, id: \.self) { language in
            Button {
                selection = language
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Text(optionTitle(language))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    if language == selection {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(
                language == selection ? "Selected" : ""
            )
        }
        .overlay {
            if filteredOptions.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Search Languages")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("ios.settings.language-selection")
    }

    private var filteredOptions: [TranscriptionLanguage] {
        options.filter {
            IOSLanguageSelectionPresentation.matches(
                $0,
                automaticTitle: automaticTitle,
                query: query
            )
        }
    }

    private func optionTitle(
        _ language: TranscriptionLanguage
    ) -> String {
        IOSLanguageSelectionPresentation.title(
            for: language,
            automaticTitle: automaticTitle
        )
    }
}
