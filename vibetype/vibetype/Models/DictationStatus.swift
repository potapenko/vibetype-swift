//
//  DictationStatus.swift
//  vibetype
//
//  Created by Eugene Potapenko on 6/20/26.
//

enum DictationStatus: Equatable {
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
            return "Listening..."
        case .transcribing:
            return "Transcribing audio..."
        case .success(let transcript):
            return transcript.isEmpty ? "No transcript available." : transcript
        case .failure(let message):
            return message
        }
    }

    var lastTranscriptText: String? {
        switch self {
        case .success(let transcript):
            return transcript
        default:
            return nil
        }
    }
}
