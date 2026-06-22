//
//  DictationStatus.swift
//  vibetype
//
//  Created by Eugene Potapenko on 6/20/26.
//

enum DictationStatus: Equatable {
    private static let lastTranscriptPreviewLimit = 140

    case idle
    case recording
    case transcribing
    case success(transcript: String)
    case failure(message: String)

    var menuStatusText: String {
        switch self {
        case .idle:
            return "Ready"
        case .recording:
            return "Recording..."
        case .transcribing:
            return "Transcribing..."
        case .success:
            return "Done"
        case .failure:
            return "Error"
        }
    }

    var recordingActionTitle: String {
        switch self {
        case .recording:
            return "Stop Recording"
        default:
            return "Start Recording"
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

    var detailText: String? {
        switch self {
        case .idle:
            return "Recording is not implemented in this build."
        case .recording:
            return "Recording placeholder active. Microphone input is not captured in this build."
        case .transcribing:
            return "Transcribing audio..."
        case .success:
            return lastTranscriptText ?? "No transcript available."
        case .failure(let message):
            return message
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

    var lastTranscriptMenuText: String {
        guard let transcript = lastTranscriptText else {
            return "No transcript yet."
        }

        guard transcript.count > Self.lastTranscriptPreviewLimit else {
            return transcript
        }

        let previewEndIndex = transcript.index(
            transcript.startIndex,
            offsetBy: Self.lastTranscriptPreviewLimit
        )
        return "\(transcript[..<previewEndIndex])..."
    }

    var canCopyLastTranscript: Bool {
        lastTranscriptText != nil
    }

    var placeholderRecordingActionResult: DictationStatus {
        switch self {
        case .idle, .success, .failure:
            return .recording
        case .recording:
            return .idle
        case .transcribing:
            return .transcribing
        }
    }
}
