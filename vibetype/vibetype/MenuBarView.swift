//
//  MenuBarView.swift
//  vibetype
//
//  Created by Eugene Potapenko on 6/20/26.
//

import AppKit
import SwiftUI

struct MenuBarView: View {
    @State private var statusMessage = "Ready"
    @State private var placeholderMessage = "Recording is not implemented in this build."

    var body: some View {
        Text("VibeType")
            .font(.headline)

        Text(statusMessage)
            .foregroundStyle(.secondary)

        Divider()

        Button("Start Recording") {
            statusMessage = "Recording unavailable"
            placeholderMessage = "Start Recording is a placeholder until the recorder task lands."
        }

        Text(placeholderMessage)
            .foregroundStyle(.secondary)

        Divider()

        Button("Quit VibeType") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

#Preview {
    MenuBarView()
}
