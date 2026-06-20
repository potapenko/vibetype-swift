//
//  VibeTypeIOSApp.swift
//  vibetype-iOS
//
//  Created by Codex on 6/21/26.
//

import SwiftUI

@main
struct VibeTypeIOSApp: App {
    var body: some Scene {
        WindowGroup {
            VibeTypeIOSStatusView()
        }
    }
}

private struct VibeTypeIOSStatusView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("VibeType", systemImage: "mic.fill")
                            .font(.title2.weight(.semibold))

                        Text("iOS containing app skeleton")
                            .font(.headline)

                        Text(
                            "Keyboard setup, recording, transcription, and text insertion are not enabled in this target yet."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Current Scope") {
                    Label("Containing app only", systemImage: "iphone")
                    Label("No keyboard extension", systemImage: "keyboard")
                    Label("No microphone or network flow", systemImage: "lock.shield")
                }
            }
            .navigationTitle("VibeType")
        }
    }
}

#Preview {
    VibeTypeIOSStatusView()
}
