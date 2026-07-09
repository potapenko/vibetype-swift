import Foundation

public enum RecordingStopTailDuration: String, CaseIterable, Codable, Equatable, Sendable {
    case off = "off"
    case milliseconds500 = "milliseconds500"
    case seconds1 = "seconds1"
    case seconds1_5 = "seconds1_5"
    case seconds2 = "seconds2"

    public var duration: TimeInterval {
        switch self {
        case .off:
            return 0
        case .milliseconds500:
            return 0.5
        case .seconds1:
            return 1
        case .seconds1_5:
            return 1.5
        case .seconds2:
            return 2
        }
    }
}

public struct VoiceSessionPreferences: Equatable, Sendable {
    public static let maximumUtteranceDuration: TimeInterval = 300
    public static let quickSessionDuration: TimeInterval = 300
    public static let defaults = VoiceSessionPreferences()

    public var audioCuesEnabled: Bool
    public var recordingStopTailDuration: RecordingStopTailDuration

    public init(
        audioCuesEnabled: Bool = true,
        recordingStopTailDuration: RecordingStopTailDuration = .off
    ) {
        self.audioCuesEnabled = audioCuesEnabled
        self.recordingStopTailDuration = recordingStopTailDuration
    }
}
