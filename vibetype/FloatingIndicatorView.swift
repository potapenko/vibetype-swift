//
//  FloatingIndicatorView.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import SwiftUI

struct FloatingIndicatorView: View {
    let presentation: FloatingIndicatorPresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPulsing = false
    @State private var isRotating = false

    var body: some View {
        indicator
            .frame(width: 72, height: 72)
            .onAppear {
                guard !reduceMotion else {
                    return
                }

                withAnimation(
                    .easeInOut(duration: presentation.phase.pulseDuration)
                        .repeatForever(autoreverses: true)
                ) {
                    isPulsing.toggle()
                }
                withAnimation(
                    .linear(duration: presentation.phase.rotationDuration)
                        .repeatForever(autoreverses: false)
                ) {
                    isRotating.toggle()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private var indicator: some View {
        if reduceMotion {
            Image(presentation.phase.fullAssetName)
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                animatedOrbit

                Image(presentation.phase.coreAssetName)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(isPulsing ? presentation.phase.corePulseScale : 1)
            }
            .scaleEffect(isPulsing ? presentation.phase.containerPulseScale : 1)
        }
    }

    @ViewBuilder
    private var animatedOrbit: some View {
        switch presentation.phase {
        case .recording:
            recordingOrbit
                .rotationEffect(.degrees(isRotating ? 360 : 0))
        case .transcribing:
            transcribingOrbit
                .rotationEffect(.degrees(isRotating ? 360 : 0))
        }
    }

    private var recordingOrbit: some View {
        ZStack {
            Circle()
                .stroke(presentation.phase.accent.opacity(0.45), lineWidth: 1.1)
                .frame(width: 66, height: 66)

            Circle()
                .stroke(presentation.phase.accent.opacity(0.28), lineWidth: 1)
                .frame(width: 58, height: 58)

            Circle()
                .fill(presentation.phase.accent)
                .frame(width: 7, height: 7)
                .shadow(color: presentation.phase.accent.opacity(0.8), radius: 4)
                .offset(y: -33)
        }
    }

    private var transcribingOrbit: some View {
        ZStack {
            Circle()
                .stroke(presentation.phase.accent.opacity(0.35), lineWidth: 1)
                .frame(width: 62, height: 62)

            ForEach(0..<24, id: \.self) { index in
                Circle()
                    .fill(
                        presentation.phase.accent.opacity(
                            index.isMultiple(of: 3) ? 0.9 : 0.48
                        )
                    )
                    .frame(
                        width: index.isMultiple(of: 4) ? 4.8 : 3.2,
                        height: index.isMultiple(of: 4) ? 4.8 : 3.2
                    )
                    .offset(y: -33)
                    .rotationEffect(.degrees(Double(index) * 15))
            }
        }
    }
}

private extension FloatingIndicatorPresentation.Phase {
    var fullAssetName: String {
        switch self {
        case .recording:
            return "ActivityRecordingIndicator"
        case .transcribing:
            return "ActivityTranscribingIndicator"
        }
    }

    var coreAssetName: String {
        switch self {
        case .recording:
            return "ActivityRecordingCore"
        case .transcribing:
            return "ActivityTranscribingCore"
        }
    }

    var accent: Color {
        switch self {
        case .recording:
            return Color(red: 0.22, green: 0.89, blue: 1.0)
        case .transcribing:
            return Color(red: 0.67, green: 0.34, blue: 1.0)
        }
    }

    var pulseDuration: Double {
        switch self {
        case .recording:
            return 0.78
        case .transcribing:
            return 1.05
        }
    }

    var rotationDuration: Double {
        switch self {
        case .recording:
            return 1.8
        case .transcribing:
            return 2.4
        }
    }

    var corePulseScale: CGFloat {
        switch self {
        case .recording:
            return 1.035
        case .transcribing:
            return 1.02
        }
    }

    var containerPulseScale: CGFloat {
        switch self {
        case .recording:
            return 1.025
        case .transcribing:
            return 1.015
        }
    }
}

#Preview("Recording") {
    FloatingIndicatorView(
        presentation: FloatingIndicatorPresentation(
            phase: .recording,
            title: "Recording"
        )
    )
    .padding()
}

#Preview("Transcribing") {
    FloatingIndicatorView(
        presentation: FloatingIndicatorPresentation(
            phase: .transcribing,
            title: "Transcribing"
        )
    )
    .padding()
}
