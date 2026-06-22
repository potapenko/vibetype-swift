//
//  FloatingIndicatorView.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import SwiftUI

struct FloatingIndicatorView: View {
    let presentation: FloatingIndicatorPresentation

    @State private var isPulsing = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.regularMaterial)
                .overlay {
                    Circle()
                        .stroke(.separator.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .scaleEffect(isPulsing ? 1.05 : 0.94)
                .opacity(isPulsing ? 1 : 0.86)

            Image(systemName: presentation.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)

            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.8), lineWidth: 1.5)
                }
                .offset(x: -7, y: 7)
        }
        .frame(width: 72, height: 72)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.78).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
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
            systemImage: "mic.fill"
        )
    )
    .padding()
}
