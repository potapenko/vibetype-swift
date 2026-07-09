//
//  KeyboardBridgeProbeView.swift
//  HoldType-iOS
//
//  Created by Codex on 7/9/26.
//

import SwiftUI

struct KeyboardBridgeProbeView: View {
    @State private var statusMessage = "No sample has been published in this run."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Phase 0 Validation")
                    .font(.headline)

                Text(
                    "Publish a short local sample, switch to the HoldType keyboard, "
                    + "then tap Insert latest."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Button(action: publishSampleTranscript) {
                Label("Publish Sample Transcript", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Stores a short local transcript in the HoldType App Group")

            Label(statusMessage, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("This probe does not use the microphone, network, or OpenAI.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 0.5)
        }
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
            statusMessage = "Sample published. It expires in 10 minutes."
        } catch {
            statusMessage = "The shared App Group is unavailable in this build."
        }
    }
}

#Preview {
    KeyboardBridgeProbeView()
        .padding()
        .background(Color(.systemGroupedBackground))
}
