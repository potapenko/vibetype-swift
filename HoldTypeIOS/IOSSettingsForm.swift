import SwiftUI

struct IOSSettingsForm<Content: View>: View {
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
        IOSSettingsAttentionScrollView(attentionTarget: attentionTarget) {
            Form {
                content
            }
        }
    }
}

#Preview("Settings form") {
    IOSSettingsForm {
        Section("Example") {
            Text("Local preview content")
        }
    }
}
