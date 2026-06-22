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
        case transcribing
    }

    let phase: Phase
    let title: String

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
                title: "Recording"
            )
        case .transcribing:
            return FloatingIndicatorPresentation(
                phase: .transcribing,
                title: "Transcribing"
            )
        case .success, .failure:
            return nil
        }
    }
}
