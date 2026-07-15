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
            Section("What OpenAI Receives") {
                disclosurePoint(
                    "The recording you choose to transcribe, along with your "
                        + "selected language and optional instructions.",
                    image: "waveform"
                )
                disclosurePoint(
                    "If correction or translation is enabled, the transcript "
                        + "may be sent again to complete that action.",
                    image: "character.bubble"
                )
                disclosurePoint(
                    "Your saved API key is used to send these requests directly "
                        + "to OpenAI.",
                    image: "key.fill"
                )
            }

            Section("What Stays Private") {
                disclosurePoint(
                    "Ordinary typing and surrounding text from other apps are "
                        + "not sent to OpenAI.",
                    image: "keyboard"
                )
                disclosurePoint(
                    "The keyboard never receives your API key or recordings.",
                    image: "lock.shield"
                )
            }

            Section("On This iPhone") {
                disclosurePoint(
                    "A recording is kept only while it is needed for processing "
                        + "or recovery. Recording Cache is on by default and "
                        + "can keep the 20 newest completed recordings for "
                        + "local History playback.",
                    image: "waveform.badge.exclamationmark"
                )
                disclosurePoint(
                    "History keeps up to 20 successful transcriptions. Failed "
                        + "attempts are not added to History or Recording Cache.",
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
