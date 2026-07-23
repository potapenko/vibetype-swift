import HoldTypeDomain
import SwiftUI

struct FixesPaletteView: View {
    @ObservedObject var model: FixesPaletteModel

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            actionList

            if let status = model.statusPresentation {
                Divider()

                FixesPaletteStatusBanner(presentation: status)
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .onAppear {
            isSearchFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("HoldType Fixes")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Fixes", systemImage: "wand.and.stars")
                    .font(.headline)

                Spacer()

                Text("⌥J")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel("Option J")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(
                    "Search Fixes",
                    text: Binding(
                        get: { model.searchText },
                        set: model.setSearchText
                    )
                )
                .textFieldStyle(.plain)
                .focused($isSearchFocused)

                if !model.searchText.isEmpty {
                    Button {
                        model.setSearchText("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(.quaternary.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(12)
    }

    @ViewBuilder
    private var actionList: some View {
        if model.visibleActions.isEmpty {
            ContentUnavailableView(
                "No Matching Fixes",
                systemImage: "magnifyingglass",
                description: Text("Try another search.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(model.visibleActions) { action in
                            FixesPaletteActionRow(
                                action: action,
                                isSelected: action.id == model.selectedActionID,
                                isProcessing: isProcessing(action.id),
                                isEnabled: model.status.allowsActionActivation
                            ) {
                                model.selectAction(id: action.id)
                                model.activateSelection()
                            }
                            .id(action.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: model.selectedActionID) { _, selectedActionID in
                    guard let selectedActionID else {
                        return
                    }

                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(selectedActionID, anchor: .center)
                    }
                }
            }
        }
    }

    private func isProcessing(_ actionID: String) -> Bool {
        if case .processing(let processingActionID) = model.status {
            return processingActionID == actionID
        }

        return false
    }
}

private struct FixesPaletteActionRow: View {
    let action: FixesPaletteActionPresentation
    let isSelected: Bool
    let isProcessing: Bool
    let isEnabled: Bool
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 10) {
                Image(systemName: action.systemImageName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Color.accentColor.opacity(isSelected ? 0.14 : 0),
                        in: RoundedRectangle(cornerRadius: 6)
                    )

                Text(action.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isProcessing {
                    ProgressView()
                        .controlSize(.small)
                } else if isSelected {
                    Image(systemName: "return")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 38)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor.opacity(0.11) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || isProcessing ? 1 : 0.52)
        .accessibilityLabel(action.title)
        .accessibilityHint(isEnabled ? "Applies this Fix" : "Unavailable")
    }
}

private struct FixesPaletteStatusBanner: View {
    let presentation: FixesPaletteStatusPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if presentation.showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 1)
            } else if let systemImageName = presentation.systemImageName {
                Image(systemName: systemImageName)
                    .foregroundStyle(accentColor)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.caption)
                    .fontWeight(.semibold)

                if let message = presentation.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var accentColor: Color {
        switch presentation.tone {
        case .neutral:
            return .accentColor
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

private struct FixesPalettePreviewContainer: View {
    @StateObject private var model: FixesPaletteModel

    @MainActor
    init(status: FixesPaletteStatus) {
        _model = StateObject(
            wrappedValue: FixesPaletteModel(
                catalog: .defaults,
                status: status,
                onActivate: { _ in },
                onDismiss: {}
            )
        )
    }

    var body: some View {
        FixesPaletteView(model: model)
            .frame(width: 360, height: 392)
            .padding(30)
    }
}

#Preview("Ready") {
    FixesPalettePreviewContainer(status: .ready)
}

#Preview("Failure") {
    FixesPalettePreviewContainer(
        status: .failure(
            message: "The request could not be completed. Choose a Fix to retry.",
            allowsRetry: true
        )
    )
}

#Preview("Stale Target") {
    FixesPalettePreviewContainer(
        status: .staleTarget(
            message: "The original text changed, so HoldType left it unchanged."
        )
    )
}
