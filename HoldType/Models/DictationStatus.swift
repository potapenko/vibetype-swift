//
//  DictationStatus.swift
//  HoldType
//
//  Created by Eugene Potapenko on 6/20/26.
//

import Foundation
import HoldTypeDomain

enum DictationStatus: Equatable {
    case idle
    case recording
    case transcribing
    case success(transcript: String)
    case failure(message: String)

    var voiceWorkPhase: VoiceWorkPhase {
        switch self {
        case .idle, .success, .failure:
            return .inactive
        case .recording:
            return .listening
        case .transcribing:
            return .processing
        }
    }

    var menuStatusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording\u{2026}"
        case .transcribing:
            return "Transcribing\u{2026}"
        case .success:
            return "Ready"
        case .failure(let message):
            return Self.compactFailureStatusText(for: message)
        }
    }

    var recordingActionTitle: String {
        switch self {
        case .recording:
            return "Stop Recording"
        default:
            return "Transcribe"
        }
    }

    var recordingActionShortcutHint: String? {
        switch self {
        case .recording:
            return nil
        default:
            return GlobalHotkeyShortcut.defaultDictation.menuHoldText
        }
    }

    var isRecordingActionEnabled: Bool {
        switch self {
        case .transcribing:
            return false
        default:
            return true
        }
    }

    var lastTranscriptText: String? {
        switch self {
        case .success(let transcript):
            return AcceptedTranscript.nonEmptyNormalizedText(from: transcript)
        default:
            return nil
        }
    }

    static func compactFailureStatusText(for message: String) -> String {
        let reason = compactFailureReason(for: message)
        switch reason.kind {
        case .setup:
            return reason.text
        case .error:
            return "Error: \(reason.text)"
        }
    }

    private static func compactFailureReason(for message: String) -> CompactFailureReason {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return CompactFailureReason(text: "Something went wrong", kind: .error)
        }

        let normalized = trimmedMessage.lowercased()
        if normalized.contains("api key") {
            if normalized.contains("rejected") {
                return CompactFailureReason(text: "API key rejected", kind: .error)
            }

            if normalized.contains("could not be read") || normalized.contains("unavailable") {
                return CompactFailureReason(text: "API key unavailable", kind: .error)
            }

            if normalized.contains("missing")
                || normalized.contains("required")
                || normalized.contains("needs")
                || normalized.contains("enter")
                || normalized.contains("saved in settings") {
                return CompactFailureReason(text: "API key required", kind: .setup)
            }
        }

        if normalized.contains("microphone") {
            if normalized.contains("permission")
                || normalized.contains("access")
                || normalized.contains("not allowed") {
                return CompactFailureReason(text: "Microphone permission required", kind: .setup)
            }

            if normalized.contains("unavailable") {
                return CompactFailureReason(text: "Microphone unavailable", kind: .error)
            }
        }

        if normalized.contains("accessibility permission") {
            return CompactFailureReason(text: "Accessibility permission required", kind: .setup)
        }

        if normalized.contains("complete required setup") {
            return CompactFailureReason(text: "Setup required", kind: .setup)
        }

        if normalized.contains("recording was too short") {
            return CompactFailureReason(text: "Recording too short", kind: .error)
        }

        if normalized.contains("no audio was captured") {
            return CompactFailureReason(text: "No audio captured", kind: .error)
        }

        if normalized.contains("no speech text") || normalized.contains("no text detected") {
            return CompactFailureReason(text: "No text detected", kind: .error)
        }

        if normalized.contains("network is unavailable") {
            return CompactFailureReason(text: "Network unavailable", kind: .error)
        }

        if normalized.contains("timed out") {
            return CompactFailureReason(text: "Transcription timed out", kind: .error)
        }

        if normalized.contains("rate limit") {
            return CompactFailureReason(text: "Rate limited", kind: .error)
        }

        if normalized.contains("openai is unavailable") {
            return CompactFailureReason(text: "OpenAI unavailable", kind: .error)
        }

        return CompactFailureReason(
            text: trimmedMessage.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
            kind: .error
        )
    }
}

private struct CompactFailureReason {
    let text: String
    let kind: CompactFailureKind
}

private enum CompactFailureKind {
    case setup
    case error
}
