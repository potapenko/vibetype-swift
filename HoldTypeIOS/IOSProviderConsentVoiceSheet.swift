import SwiftUI

struct IOSProviderConsentVoiceSheet: View {
    let promptID: IOSProviderConsentPromptID
    let sceneOwner: IOSForegroundVoiceSceneHostOwner
    let consentOwner: IOSProviderConsentPresentationOwner

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("OpenAI Processing")
                                .font(.headline)
                            Text(
                                "HoldType sends the recording to OpenAI only "
                                    + "after you explicitly start Voice."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(.tint)
                    }
                }

                IOSProviderConsentDisclosureSections()

                Section {
                    switch phase {
                    case .review:
                        Button {
                            consentOwner.acceptVoicePrompt(
                                promptID,
                                from: sceneOwner
                            )
                        } label: {
                            Label(
                                "Accept and Continue",
                                systemImage: "checkmark"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier(
                            "ios.voice.consent.accept"
                        )

                        Button("Decline", role: .destructive) {
                            consentOwner.declineVoicePrompt(
                                promptID,
                                from: sceneOwner
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier(
                            "ios.voice.consent.decline"
                        )
                    case .accepting:
                        progressRow("Saving consent…")
                    case .declining:
                        progressRow("Saving your decision…")
                    }
                } footer: {
                    Text(
                        "You can review or withdraw this decision later in "
                            + "Settings → Privacy & Permissions."
                    )
                }
            }
            .navigationTitle("Privacy Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase == .review {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Not Now") {
                            consentOwner.dismissVoicePrompt(
                                promptID,
                                from: sceneOwner
                            )
                        }
                        .accessibilityIdentifier(
                            "ios.voice.consent.not-now"
                        )
                    }
                }
            }
        }
        .interactiveDismissDisabled(phase != .review)
        .presentationDetents([.medium, .large])
        .onChange(of: phase) { _, phase in
            switch phase {
            case .review:
                break
            case .accepting:
                IOSAccessibilityAnnouncement.post("Saving consent")
            case .declining:
                IOSAccessibilityAnnouncement.post("Saving your decision")
            }
        }
        .accessibilityIdentifier("ios.voice.consent.sheet")
    }

    private var phase: IOSProviderConsentVoicePromptPhase {
        guard consentOwner.voicePrompt?.id == promptID else {
            return .review
        }
        return consentOwner.voicePrompt?.phase ?? .review
    }

    private func progressRow(_ title: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(title)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

struct IOSProviderConsentDisclosureSections: View {
    var body: some View {
        Group {
            Section("Sent to OpenAI") {
                disclosurePoint(
                    "The current recording is sent directly to OpenAI for "
                        + "transcription.",
                    image: "waveform"
                )
                disclosurePoint(
                    "The selected model and language, transcription prompt, "
                        + "dictionary spelling guidance, and enabled emoji "
                        + "hints may be included.",
                    image: "text.bubble"
                )
                disclosurePoint(
                    "Enabled correction or translation may send the transcript "
                        + "and selected prompt in additional requests. "
                        + "Translation also sends the resolved language route.",
                    image: "character.bubble"
                )
                disclosurePoint(
                    "Your API key is read from the containing app’s Keychain "
                        + "and sent directly to OpenAI to authenticate requests.",
                    image: "key.fill"
                )
            }

            Section("Not Sent") {
                disclosurePoint(
                    "Ordinary keystrokes and surrounding text from the host "
                        + "field are not sent.",
                    image: "keyboard"
                )
                disclosurePoint(
                    "Local emoji definitions and replacement rules are not sent "
                        + "as correction or translation configuration.",
                    image: "lock.shield"
                )
                disclosurePoint(
                    "HoldType does not copy the API key into the keyboard, App "
                        + "Group, logs, or a HoldType server.",
                    image: "server.rack"
                )
            }

            Section("Local Retention in P4") {
                disclosurePoint(
                    "Completed audio is protected locally until accepted-output "
                        + "cleanup, or until you choose Pending Retry or Discard.",
                    image: "waveform.badge.exclamationmark"
                )
                disclosurePoint(
                    "Accepted text stays in app-private Latest Result until "
                        + "confirmed Clear, atomic replacement, or its 24-hour "
                        + "safety expiry.",
                    image: "doc.text"
                )
                disclosurePoint(
                    "P4 does not add accepted or failed History rows or a "
                        + "Recording Cache.",
                    image: "clock.arrow.circlepath"
                )
            }
        }
    }

    private func disclosurePoint(
        _ text: String,
        image: String
    ) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: image)
                .foregroundStyle(.tint)
        }
        .accessibilityElement(children: .combine)
    }
}
