import Foundation
import Testing
@testable import HoldTypeDomain

struct VoiceSessionPreferencesTests {
    @Test func publicValuesAreSendable() {
        requireSendable(RecordingStopTailDuration.self)
        requireSendable(VoiceSessionPreferences.self)
    }

    @Test func defaultsMatchTheVoiceSessionContract() {
        let preferences = VoiceSessionPreferences()

        #expect(preferences == .defaults)
        #expect(preferences.audioCuesEnabled)
        #expect(preferences.recordingStopTailDuration == .off)
        #expect(VoiceSessionPreferences.maximumUtteranceDuration == 300)
        #expect(VoiceSessionPreferences.quickSessionDuration == 300)
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
            recordingStopTailDuration: .seconds1_5
        )

        #expect(preferences.audioCuesEnabled == false)
        #expect(preferences.recordingStopTailDuration == .seconds1_5)

        preferences.audioCuesEnabled = true
        preferences.recordingStopTailDuration = .milliseconds500
        #expect(preferences == VoiceSessionPreferences(
            audioCuesEnabled: true,
            recordingStopTailDuration: .milliseconds500
        ))
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
