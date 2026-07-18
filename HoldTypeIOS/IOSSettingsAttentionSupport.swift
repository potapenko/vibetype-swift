import SwiftUI
import UIKit

struct IOSSettingsAttentionTarget: Hashable, Sendable {
    let attention: IOSSettingsAttention
    let field: IOSSettingsField

    init(
        _ attention: IOSSettingsAttention,
        field: IOSSettingsField? = nil
    ) {
        self.attention = attention
        self.field = field ?? attention.defaultField
    }

}
struct IOSSettingsAttentionScrollView<Content: View>: View {
    let attentionTarget: IOSSettingsAttentionTarget?
    private let content: Content

    init(
        attentionTarget: IOSSettingsAttentionTarget? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.attentionTarget = attentionTarget
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            content
            .task(id: attentionTarget) {
                guard let attentionTarget else { return }
                await Task.yield()
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(attentionTarget.field, anchor: .center)
                }
                await Task.yield()
                UIAccessibility.post(
                    notification: .layoutChanged,
                    argument: nil
                )
                iosAnnounceSettingsStatus(
                    attentionTarget.attention.title
                        + ". "
                        + attentionTarget.attention.detail
                )
            }
        }
    }
}

private struct IOSSettingsFieldModifier: ViewModifier {
    let field: IOSSettingsField
    let attentionTarget: IOSSettingsAttentionTarget?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if attentionTarget?.field == field,
               let attention = attentionTarget?.attention {
                IOSSettingsAttentionCallout(attention: attention)
            }
        }
        .id(field)
    }
}

private struct IOSSettingsAttentionCallout: View {
    let attention: IOSSettingsAttention

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(attention.title)
                    .font(.subheadline.weight(.semibold))
                Text(attention.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            "ios.settings.attention.\(attention.rawValue)"
        )
    }
}

private struct IOSSettingsEditorPersistentStatus: View {
    let phase: IOSSettingsEditorPhase

    @ViewBuilder
    var body: some View {
        switch phase {
        case .saveFailed:
            statusLabel(
                "Not Saved",
                systemImage: "exclamationmark.triangle.fill",
                color: .red,
                identifier: "ios.settings.editor.persistent-save-failed"
            )
        case .changedElsewhere:
            statusLabel(
                "Changed Elsewhere",
                systemImage: "arrow.triangle.2.circlepath",
                color: .orange,
                identifier: "ios.settings.editor.persistent-changed"
            )
        case .validationBlocked:
            statusLabel(
                "Changes Not Applied",
                systemImage: "exclamationmark.circle.fill",
                color: .orange,
                identifier: "ios.settings.editor.persistent-validation"
            )
        case .idle, .pending, .saving, .saved:
            EmptyView()
        }
    }

    private func statusLabel(
        _ title: String,
        systemImage: String,
        color: Color,
        identifier: String
    ) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
            .font(.footnote.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .accessibilityIdentifier(identifier)
    }
}

private struct IOSSettingsAutosaveChrome: ViewModifier {
    let phase: IOSSettingsEditorPhase

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                IOSSettingsEditorPersistentStatus(phase: phase)
            }
    }
}

extension View {
    func iosSettingsField(
        _ field: IOSSettingsField,
        attentionTarget: IOSSettingsAttentionTarget? = nil
    ) -> some View {
        modifier(
            IOSSettingsFieldModifier(
                field: field,
                attentionTarget: attentionTarget
            )
        )
    }

    func iosSettingsAutosaveChrome(
        phase: IOSSettingsEditorPhase
    ) -> some View {
        modifier(IOSSettingsAutosaveChrome(phase: phase))
    }
}

@MainActor
func iosAnnounceSettingsStatus(_ message: String) {
    UIAccessibility.post(
        notification: .announcement,
        argument: message
    )
}

#Preview("Settings attention scroll view") {
    IOSSettingsAttentionScrollView {
        ScrollView {
            Text("Local preview content")
                .frame(maxWidth: .infinity)
                .padding()
        }
    }
}
