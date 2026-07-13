//
//  KeyboardBridgeProbeView.swift
//  HoldType-iOS
//
//  Created by Codex on 7/9/26.
//

#if DEBUG
import SwiftUI
import UIKit

private struct KeyboardBridgeProbeVisibilityKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var showsKeyboardBridgeProbe: Bool {
        get { self[KeyboardBridgeProbeVisibilityKey.self] }
        set { self[KeyboardBridgeProbeVisibilityKey.self] = newValue }
    }
}

struct KeyboardBridgeProbeView: View {
    @State private var statusMessage =
        "No keyboard test sample has been published in this run."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Publish a short local sample, focus the practice field, "
                + "switch to HoldType with Globe, then tap Insert latest."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: publishSampleTranscript) {
                Label(
                    "Publish Keyboard Test Sample",
                    systemImage: "square.and.arrow.up"
                )
            }
            .accessibilityHint(
                "Stores a short, expiring local transcript for the HoldType keyboard"
            )
            .accessibilityIdentifier("ios.voice.publish-practice-sample")

            Label(statusMessage, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("This local test does not use the microphone, network, or OpenAI.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func publishSampleTranscript() {
        do {
            let now = Date()
            let transcript = try KeyboardBridgeTranscript(
                text: "HoldType keyboard bridge is working.",
                createdAt: now
            )
            let store = try KeyboardBridgeStore.appGroup()
            let snapshot = KeyboardBridgeSnapshot(
                revision: try store.nextRevision(),
                sessionID: UUID(),
                phase: .transcriptReady,
                updatedAt: now,
                expiresAt: now.addingTimeInterval(10 * 60),
                acceptedTranscript: transcript
            )

            try store.save(snapshot)
            publishStatus(
                "Sample published. It expires in 10 minutes."
            )
        } catch {
            publishStatus(
                "The sample couldn’t be published. Try again."
            )
        }
    }

    private func publishStatus(_ message: String) {
        statusMessage = message
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

#Preview {
    KeyboardBridgeProbeView()
        .padding()
        .background(Color(.systemGroupedBackground))
}
#endif
