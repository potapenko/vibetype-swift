import SwiftUI

struct IOSVoiceHomeView: View {
    @State private var practiceText = ""

    let secureProviderAvailability: IOSSecureProviderAvailability

    var body: some View {
        List {
            Section("Getting Started") {
                IOSSetupSummaryRow(
                    systemImage: "keyboard",
                    title: "Keyboard practice",
                    detail: "Use the practice field below with any keyboard."
                )
                IOSSetupSummaryRow(
                    systemImage: "key.fill",
                    title: openAISetupTitle,
                    detail: openAISetupDetail
                )
                IOSSetupSummaryRow(
                    systemImage: "mic.slash.fill",
                    title: "Microphone access",
                    detail: "Permission is requested only after an explicit Start."
                )
            }

            Section("Voice Capture") {
                Label(
                    "Voice recording is not available in this build.",
                    systemImage: "mic.slash"
                )
                .foregroundStyle(.secondary)

                Text(
                    "Opening this screen never requests microphone access, "
                    + "starts recording, or contacts OpenAI."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Keyboard Practice") {
                TextField(
                    "Tap here and type with the HoldType keyboard",
                    text: $practiceText,
                    axis: .vertical
                )
                .lineLimit(4...8)
                .textInputAutocapitalization(.sentences)
                .accessibilityIdentifier("ios.voice.practice-field")

                if !practiceText.isEmpty {
                    Button("Clear Practice Field", role: .destructive) {
                        practiceText = ""
                    }
                }

                KeyboardBridgeProbeView()
            }
        }
        .navigationTitle("Voice")
        .accessibilityIdentifier(
            IOSContainingAppDestination.voice.accessibilityIdentifier
        )
    }

    private var openAISetupTitle: String {
        switch secureProviderAvailability {
        case .available:
            "OpenAI setup"
        case .unavailable:
            "OpenAI setup unavailable"
        }
    }

    private var openAISetupDetail: String {
        switch secureProviderAvailability {
        case .available:
            "Credential status is not checked on this screen."
        case .unavailable:
            "Secure provider settings are unavailable in this build."
        }
    }
}

private struct IOSSetupSummaryRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
        }
        .accessibilityElement(children: .combine)
    }
}
