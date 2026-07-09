import HoldTypeDomain

typealias RecordingStopTailDuration = HoldTypeDomain.RecordingStopTailDuration
typealias VoiceSessionPreferences = HoldTypeDomain.VoiceSessionPreferences

extension RecordingStopTailDuration {
    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .milliseconds500:
            return "0.5 seconds"
        case .seconds1:
            return "1.0 second"
        case .seconds1_5:
            return "1.5 seconds"
        case .seconds2:
            return "2.0 seconds"
        }
    }
}
