import Foundation
import Testing
@testable import HoldTypeDomain

struct VoiceSessionPreferencesTests {
    @Test func publicValuesAreSendable() {
        requireSendable(RecordingStopTailDuration.self)
        requireSendable(RecordingDurationLimit.self)
        requireSendable(VoiceSessionWarningUrgency.self)
        requireSendable(VoiceSessionWarning.self)
        requireSendable(VoiceSessionCountdown.self)
        requireSendable(VoiceSessionPreferences.self)
    }

    @Test func defaultsMatchTheVoiceSessionContract() {
        let preferences = VoiceSessionPreferences()

        #expect(preferences == .defaults)
        #expect(preferences.audioCuesEnabled)
        #expect(preferences.recordingStopTailDuration == .off)
        #expect(preferences.recordingDurationLimit == .default)
        #expect(preferences.recordingDurationLimit.minutes == 5)
        #expect(preferences.recordingDurationLimit.duration == 300)
        #expect(VoiceSessionPreferences.quickSessionDuration == 300)
    }

    @Test func durationLimitValidatesClampsAndDerivesRuntimeBounds() {
        #expect(RecordingDurationLimit.minimumMinutes == 1)
        #expect(RecordingDurationLimit.maximumMinutes == 15)
        #expect(RecordingDurationLimit.defaultMinutes == 5)
        #expect(RecordingDurationLimit.supportedMinutes == 1...15)
        #expect(RecordingDurationLimit.allValues.map(\.minutes) == Array(1...15))

        #expect(RecordingDurationLimit(validatingMinutes: 0) == nil)
        #expect(RecordingDurationLimit(validatingMinutes: 1)?.minutes == 1)
        #expect(RecordingDurationLimit(validatingMinutes: 15)?.minutes == 15)
        #expect(RecordingDurationLimit(validatingMinutes: 16) == nil)

        #expect(RecordingDurationLimit(minutes: Int.min).minutes == 1)
        #expect(RecordingDurationLimit(minutes: 7).minutes == 7)
        #expect(RecordingDurationLimit(minutes: Int.max).minutes == 15)
        #expect(RecordingDurationLimit(clampingMinutes: 0).minutes == 1)
        #expect(RecordingDurationLimit.clampedMinutes(16) == 15)

        let maximum = RecordingDurationLimit(minutes: 15)
        #expect(maximum.wholeSeconds == 900)
        #expect(maximum.duration == 900)
        #expect(maximum.maximumFinalizedMediaDurationMilliseconds == 902_000)
        #expect(
            RecordingDurationLimit
                .maximumSupportedFinalizedMediaDurationMilliseconds
                == 902_000
        )
        #expect(
            RecordingDurationLimit.defaultValue
                == RecordingDurationLimit.default
        )
    }

    @Test func warningScheduleMatchesTheDefaultFiveMinuteContract() {
        let schedule = VoiceSessionWarningSchedule(limit: .default)
        let expectedElapsedSeconds = [
            240,
            270,
            290,
            292,
            294,
            295,
            296,
            297,
            298,
            299,
        ]

        #expect(schedule.maximumDurationWholeSeconds == 300)
        #expect(
            VoiceSessionWarningSchedule.countdownStartRemainingWholeSeconds
                == 15
        )
        #expect(schedule.countdownStartElapsedWholeSecond == 285)
        #expect(
            schedule.warnings.map(\.elapsedWholeSeconds)
                == expectedElapsedSeconds
        )
        #expect(
            schedule.warnings.map(\.remainingWholeSeconds)
                == expectedElapsedSeconds.map { 300 - $0 }
        )
        #expect(
            schedule.warnings.map(\.urgency)
                == [.amber, .amber] + Array(repeating: .red, count: 8)
        )
    }

    @Test func warningsAndFinalFifteenSecondCountdownRemainIndependent() {
        let oneMinute = VoiceSessionWarningSchedule(
            limit: RecordingDurationLimit(minutes: 1)
        )
        #expect(oneMinute.maximumDurationWholeSeconds == 60)
        #expect(oneMinute.countdownStartElapsedWholeSecond == 45)
        #expect(oneMinute.warnings.map(\.elapsedWholeSeconds) == [
            30,
            50,
            52,
            54,
            55,
            56,
            57,
            58,
            59,
        ])
        #expect(oneMinute.warnings.map(\.remainingWholeSeconds) == [
            30,
            10,
            8,
            6,
            5,
            4,
            3,
            2,
            1,
        ])

        let fifteenMinutes = VoiceSessionWarningSchedule(
            limit: RecordingDurationLimit(minutes: 15)
        )
        #expect(fifteenMinutes.countdownStartElapsedWholeSecond == 885)
        #expect(fifteenMinutes.warnings.map(\.elapsedWholeSeconds) == [
            840,
            870,
            890,
            892,
            894,
            895,
            896,
            897,
            898,
            899,
        ])
        #expect(fifteenMinutes.warnings.map(\.remainingWholeSeconds)
            == VoiceSessionWarningSchedule.warningRemainingWholeSeconds)
    }

    @Test func warningLookupDoesNotDependOnFloatingPointEquality() {
        let schedule = VoiceSessionWarningSchedule(limit: .default)
        #expect(
            schedule.warning(atElapsedWholeSecond: 240)
                == schedule.warnings[0]
        )
        #expect(schedule.warning(atElapsedWholeSecond: 239) == nil)
        #expect(schedule.warning(atElapsedWholeSecond: 241) == nil)
    }

    @Test func countdownUsesWholeSecondsAndChangesUrgencyAtTenRemaining() {
        let schedule = VoiceSessionWarningSchedule(limit: .default)
        #expect(schedule.countdown(
            atElapsedWholeSecond: 284
        ) == nil)
        #expect(schedule.countdown(
            atElapsedWholeSecond: 285
        ) == VoiceSessionCountdown(
            remainingWholeSeconds: 15,
            urgency: .amber
        ))
        #expect(schedule.countdown(
            atElapsedWholeSecond: 289
        ) == VoiceSessionCountdown(
            remainingWholeSeconds: 11,
            urgency: .amber
        ))
        #expect(schedule.countdown(
            atElapsedWholeSecond: 290
        ) == VoiceSessionCountdown(
            remainingWholeSeconds: 10,
            urgency: .red
        ))
        #expect(schedule.countdown(
            atElapsedWholeSecond: 299
        ) == VoiceSessionCountdown(
            remainingWholeSeconds: 1,
            urgency: .red
        ))
        #expect(schedule.countdown(
            atElapsedWholeSecond: 300
        ) == nil)

        let oneMinute = VoiceSessionWarningSchedule(
            limit: RecordingDurationLimit(minutes: 1)
        )
        #expect(oneMinute.countdown(
            atElapsedWholeSecond: 44
        ) == nil)
        #expect(oneMinute.countdown(
            atElapsedWholeSecond: 45
        ) == VoiceSessionCountdown(
            remainingWholeSeconds: 15,
            urgency: .amber
        ))
        #expect(oneMinute.countdown(
            atElapsedWholeSecond: 50
        ) == VoiceSessionCountdown(
            remainingWholeSeconds: 10,
            urgency: .red
        ))
    }

    @Test func stopTailCasesPreserveLegacyRawValuesAndDurations() {
        let expected: [(RecordingStopTailDuration, String, TimeInterval)] = [
            (.off, "off", 0),
            (.milliseconds500, "milliseconds500", 0.5),
            (.seconds1, "seconds1", 1),
            (.seconds1_5, "seconds1_5", 1.5),
            (.seconds2, "seconds2", 2),
        ]

        #expect(RecordingStopTailDuration.allCases == expected.map(\.0))
        for (tail, rawValue, duration) in expected {
            #expect(tail.rawValue == rawValue)
            #expect(tail.duration == duration)
            #expect(RecordingStopTailDuration(rawValue: rawValue) == tail)
        }
        #expect(RecordingStopTailDuration(rawValue: "legacyUnknownTail") == nil)
    }

    @Test func stopTailCodableShapeRemainsOneRawString() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for tail in RecordingStopTailDuration.allCases {
            let encoded = try encoder.encode(tail)
            #expect(String(decoding: encoded, as: UTF8.self) == "\"\(tail.rawValue)\"")
            #expect(try decoder.decode(RecordingStopTailDuration.self, from: encoded) == tail)
        }

        #expect(throws: DecodingError.self) {
            try decoder.decode(
                RecordingStopTailDuration.self,
                from: Data("\"legacyUnknownTail\"".utf8)
            )
        }
    }

    @Test func customPreferencesPreserveTheirRawValues() {
        var preferences = VoiceSessionPreferences(
            audioCuesEnabled: false,
            recordingStopTailDuration: .seconds1_5,
            recordingDurationLimit: RecordingDurationLimit(minutes: 12)
        )

        #expect(preferences.audioCuesEnabled == false)
        #expect(preferences.recordingStopTailDuration == .seconds1_5)
        #expect(preferences.recordingDurationLimit.minutes == 12)

        preferences.audioCuesEnabled = true
        preferences.recordingStopTailDuration = .milliseconds500
        preferences.recordingDurationLimit = RecordingDurationLimit(minutes: 3)
        #expect(preferences == VoiceSessionPreferences(
            audioCuesEnabled: true,
            recordingStopTailDuration: .milliseconds500,
            recordingDurationLimit: RecordingDurationLimit(minutes: 3)
        ))
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
