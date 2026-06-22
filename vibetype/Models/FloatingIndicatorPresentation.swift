//
//  FloatingIndicatorPresentation.swift
//  vibetype
//
//  Created by Codex on 6/21/26.
//

import Foundation

struct FloatingIndicatorPresentation: Equatable {
    enum Phase: Equatable {
        case recording
    }

    let phase: Phase
    let title: String
    let systemImage: String

    var accessibilityLabel: String {
        "VibeType \(title)"
    }

    static func presentation(
        for status: DictationStatus,
        settings: AppSettings
    ) -> FloatingIndicatorPresentation? {
        guard settings.showFloatingIndicator else {
            return nil
        }

        switch status {
        case .idle:
            return nil
        case .recording:
            return FloatingIndicatorPresentation(
                phase: .recording,
                title: "Recording",
                systemImage: "mic.fill"
            )
        case .transcribing, .success, .failure:
            return nil
        }
    }
}
