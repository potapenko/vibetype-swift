import Foundation

public struct SuccessfulTranscriptionUsage: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case emptyModel
        case invalidAudioDuration
    }

    public let transcriptionID: UUID
    public let model: String
    public let audioDuration: TimeInterval

    public init(
        transcriptionID: UUID,
        model: String,
        audioDuration: TimeInterval
    ) throws {
        let normalizedModel = model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedModel.isEmpty else {
            throw ValidationError.emptyModel
        }
        guard audioDuration.isFinite, audioDuration > 0 else {
            throw ValidationError.invalidAudioDuration
        }

        self.transcriptionID = transcriptionID
        self.model = normalizedModel
        self.audioDuration = audioDuration
    }
}

public protocol TranscriptionUsageRecording: AnyObject {
    @MainActor
    func recordSuccessfulTranscriptionUsage(_ usage: SuccessfulTranscriptionUsage)
}
