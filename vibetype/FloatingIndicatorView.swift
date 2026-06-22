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
    @Environment(\.colorScheme) private var colorScheme

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
            Image(presentation.phase.fullAssetName(for: colorScheme))
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                animatedOrbit

                Image(presentation.phase.coreAssetName(for: colorScheme))
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
                .stroke(
                    accent.opacity(colorScheme == .light ? 0.82 : 0.45),
                    lineWidth: colorScheme == .light ? 1.35 : 1.1
                )
                .frame(width: 66, height: 66)

            Circle()
                .stroke(
                    accent.opacity(colorScheme == .light ? 0.58 : 0.28),
                    lineWidth: colorScheme == .light ? 1.15 : 1
                )
                .frame(width: 58, height: 58)

            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .shadow(color: accent.opacity(0.8), radius: 4)
                .offset(y: -33)
        }
    }

    private var transcribingOrbit: some View {
        ZStack {
            Circle()
                .stroke(
                    accent.opacity(colorScheme == .light ? 0.68 : 0.35),
                    lineWidth: colorScheme == .light ? 1.15 : 1
                )
                .frame(width: 62, height: 62)

            ForEach(0..<24, id: \.self) { index in
                Circle()
                    .fill(
                        accent.opacity(
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

    private var accent: Color {
        presentation.phase.accent(for: colorScheme)
    }
}

private extension FloatingIndicatorPresentation.Phase {
    func fullAssetName(for colorScheme: ColorScheme) -> String {
        switch self {
        case .recording:
            return "ActivityRecordingIndicator\(assetSuffix(for: colorScheme))"
        case .transcribing:
            return "ActivityTranscribingIndicator\(assetSuffix(for: colorScheme))"
        }
    }

    func coreAssetName(for colorScheme: ColorScheme) -> String {
        switch self {
        case .recording:
            return "ActivityRecordingCore\(assetSuffix(for: colorScheme))"
        case .transcribing:
            return "ActivityTranscribingCore\(assetSuffix(for: colorScheme))"
        }
    }

    func assetSuffix(for colorScheme: ColorScheme) -> String {
        colorScheme == .light ? "Light" : ""
    }

    func accent(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .recording:
            if colorScheme == .light {
                return Color(red: 0.031, green: 0.545, blue: 0.941)
            }
            return Color(red: 0.22, green: 0.89, blue: 1.0)
        case .transcribing:
            if colorScheme == .light {
                return Color(red: 0.388, green: 0.078, blue: 0.894)
            }
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
