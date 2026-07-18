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

/// The user-selected maximum length of one retained recording attempt.
///
/// The value is stored in whole minutes so Settings can expose the complete
/// supported range without admitting an invalid runtime duration.
public struct RecordingDurationLimit: Equatable, Hashable, Sendable {
    public static let minimumMinutes = 1
    public static let maximumMinutes = 15
    public static let defaultMinutes = 5
    public static let supportedMinutes = minimumMinutes...maximumMinutes
    public static let `default` = RecordingDurationLimit(minutes: defaultMinutes)
    public static let defaultValue = `default`
    public static let maximumSupportedFinalizedMediaDurationMilliseconds =
        Int64(maximumMinutes * 60) * 1_000 + 2_000
    public static let allValues = supportedMinutes.map {
        RecordingDurationLimit(minutes: $0)
    }

    public let minutes: Int

    /// Returns `nil` rather than silently changing an invalid external value.
    public init?(validatingMinutes minutes: Int) {
        guard Self.supportedMinutes.contains(minutes) else {
            return nil
        }
        self.minutes = minutes
    }

    /// Clamps a UI or migrated persistence value to the supported range.
    public init(minutes: Int) {
        self.minutes = Self.clampedMinutes(minutes)
    }

    public init(clampingMinutes minutes: Int) {
        self.init(minutes: minutes)
    }

    public static func clampedMinutes(_ minutes: Int) -> Int {
        min(max(minutes, minimumMinutes), maximumMinutes)
    }

    public var wholeSeconds: Int {
        minutes * 60
    }

    public var duration: TimeInterval {
        TimeInterval(wholeSeconds)
    }

    /// The finalized media probe may include up to two seconds of recorder
    /// close post-roll beyond the selected capture deadline.
    public var maximumFinalizedMediaDurationMilliseconds: Int64 {
        Int64(wholeSeconds) * 1_000 + 2_000
    }
}

public enum VoiceSessionWarningUrgency: Equatable, Sendable {
    case amber
    case red
}

public struct VoiceSessionWarning: Equatable, Sendable {
    public let elapsedWholeSeconds: Int
    public let remainingWholeSeconds: Int
    public let urgency: VoiceSessionWarningUrgency

    public init(
        elapsedWholeSeconds: Int,
        remainingWholeSeconds: Int,
        urgency: VoiceSessionWarningUrgency
    ) {
        self.elapsedWholeSeconds = elapsedWholeSeconds
        self.remainingWholeSeconds = remainingWholeSeconds
        self.urgency = urgency
    }
}

public struct VoiceSessionCountdown: Equatable, Sendable {
    public let remainingWholeSeconds: Int
    public let urgency: VoiceSessionWarningUrgency

    public init(
        remainingWholeSeconds: Int,
        urgency: VoiceSessionWarningUrgency
    ) {
        self.remainingWholeSeconds = remainingWholeSeconds
        self.urgency = urgency
    }
}

/// Whole-second milestones for one bounded voice recording.
///
/// Consumers schedule or compare these integer offsets against a monotonic
/// clock; no warning depends on exact `TimeInterval` equality.
public struct VoiceSessionWarningSchedule: Equatable, Sendable {
    public static let countdownStartRemainingWholeSeconds = 15

    public static let warningRemainingWholeSeconds = [
        60,
        30,
        10,
        8,
        6,
        5,
        4,
        3,
        2,
        1,
    ]

    public let maximumDurationWholeSeconds: Int
    public let countdownStartElapsedWholeSecond: Int
    public let warnings: [VoiceSessionWarning]
    public init(limit: RecordingDurationLimit) {
        maximumDurationWholeSeconds = limit.wholeSeconds
        countdownStartElapsedWholeSecond = max(
            0,
            limit.wholeSeconds - Self.countdownStartRemainingWholeSeconds
        )
        warnings = Self.warningRemainingWholeSeconds.compactMap {
            remainingWholeSeconds in
            let elapsedWholeSeconds = limit.wholeSeconds
                - remainingWholeSeconds
            // A one-minute limit begins inside the countdown window. Do not
            // play its first warning immediately when recording starts.
            guard elapsedWholeSeconds > 0 else {
                return nil
            }
            return VoiceSessionWarning(
                elapsedWholeSeconds: elapsedWholeSeconds,
                remainingWholeSeconds: remainingWholeSeconds,
                urgency: Self.urgency(
                    remainingWholeSeconds: remainingWholeSeconds
                )
            )
        }
    }

    public func warning(
        atElapsedWholeSecond elapsedWholeSecond: Int
    ) -> VoiceSessionWarning? {
        warnings.first { $0.elapsedWholeSeconds == elapsedWholeSecond }
    }

    public func countdown(
        atElapsedWholeSecond elapsedWholeSecond: Int
    ) -> VoiceSessionCountdown? {
        guard
            elapsedWholeSecond >= countdownStartElapsedWholeSecond,
            elapsedWholeSecond < maximumDurationWholeSeconds
        else {
            return nil
        }

        return VoiceSessionCountdown(
            remainingWholeSeconds: maximumDurationWholeSeconds - elapsedWholeSecond,
            urgency: Self.urgency(
                remainingWholeSeconds:
                    maximumDurationWholeSeconds - elapsedWholeSecond
            )
        )
    }

    private static func urgency(
        remainingWholeSeconds: Int
    ) -> VoiceSessionWarningUrgency {
        remainingWholeSeconds > 10 ? .amber : .red
    }
}

public struct VoiceSessionPreferences: Equatable, Sendable {
    /// Separate lifecycle hypothesis; it is not the per-recording limit.
    public static let quickSessionDuration: TimeInterval = 300
    public static let defaults = VoiceSessionPreferences()

    public var audioCuesEnabled: Bool
    public var recordingStopTailDuration: RecordingStopTailDuration
    public var recordingDurationLimit: RecordingDurationLimit

    public init(
        audioCuesEnabled: Bool = true,
        recordingStopTailDuration: RecordingStopTailDuration = .off,
        recordingDurationLimit: RecordingDurationLimit = .default
    ) {
        self.audioCuesEnabled = audioCuesEnabled
        self.recordingStopTailDuration = recordingStopTailDuration
        self.recordingDurationLimit = recordingDurationLimit
    }
}
