import Foundation

/// Transient input to an accepted-transcript History adapter.
public struct AcceptedTranscriptHistoryRequest: Equatable, Sendable {
    public let acceptedTranscript: AcceptedTranscript
    public let transcriptionModel: String
    public let languageCode: String?
    public let audioDuration: TimeInterval?
    public let cachedAudioFileURL: URL?
    public let historyEnabled: Bool

    public init(
        acceptedTranscript: AcceptedTranscript,
        transcriptionConfiguration: TranscriptionConfiguration,
        retentionConfiguration: RetentionConfiguration,
        audioDuration: TimeInterval?,
        cachedAudioFileURL: URL?
    ) {
        self.acceptedTranscript = acceptedTranscript
        transcriptionModel = transcriptionConfiguration.resolvedModel
        languageCode = transcriptionConfiguration.resolvedLanguageCode
        self.audioDuration = audioDuration
        self.cachedAudioFileURL = retentionConfiguration.recordingCachePolicy.keepsRecordings
            ? cachedAudioFileURL
            : nil
        historyEnabled = retentionConfiguration.historyEnabled
    }
}
