//
//  FloatingIndicatorView.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import SwiftUI

struct FloatingIndicatorView: View {
    let presentation: FloatingIndicatorPresentation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(presentation.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.primary)
        .frame(width: 220, height: 58)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

#Preview("Recording") {
    FloatingIndicatorView(
        presentation: FloatingIndicatorPresentation(
            phase: .recording,
            title: "Recording",
            systemImage: "mic.fill",
            dismissalDelay: nil
        )
    )
    .padding()
}
