//
//  MenuBarView.swift
//  vibetype
//
//  Created by Eugene Potapenko on 6/20/26.
//

import AppKit
import SwiftUI

struct MenuBarView: View {
    @State private var dictationStatus = DictationStatus.idle

    var body: some View {
        Text("VibeType")
            .font(.headline)

        Text(dictationStatus.menuStatusText)
            .foregroundStyle(.secondary)

        Divider()

        Button(dictationStatus.recordingActionTitle) {
            dictationStatus = .failure(
                message: "Start Recording is a placeholder until the recorder task lands."
            )
        }
        .disabled(!dictationStatus.isRecordingActionEnabled)

        if let detailText = dictationStatus.detailText {
            Text(detailText)
                .foregroundStyle(.secondary)
        }

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
