import Foundation
import Testing

@MainActor
struct IOSVoicePlatformPlistTests {
    @Test func containingAppOwnsOnlyTheApprovedMicrophonePurposeString()
        throws {
        let app = try sourcePlist(at: "HoldTypeIOS/Info.plist")
        let keyboard = try sourcePlist(at: "HoldTypeKeyboard/Info.plist")
        let exact = "HoldType uses the microphone to record speech you "
            + "choose to transcribe."

        #expect(app["NSMicrophoneUsageDescription"] as? String == exact)
        #expect(app["NSSpeechRecognitionUsageDescription"] == nil)
        #expect(app["UIBackgroundModes"] == nil)
        #expect(keyboard["NSMicrophoneUsageDescription"] == nil)
        #expect(keyboard["NSSpeechRecognitionUsageDescription"] == nil)
        #expect(keyboard["UIBackgroundModes"] == nil)
    }

    @Test func privacyManifestsDeclareTheExactP4Boundary() throws {
        let app = try sourcePlist(at: "HoldTypeIOS/PrivacyInfo.xcprivacy")
        let keyboard = try sourcePlist(
            at: "HoldTypeKeyboard/PrivacyInfo.xcprivacy"
        )

        #expect(app["NSPrivacyTracking"] as? Bool == false)
        #expect(
            (app["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true
        )
        let collected = try #require(
            app["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
        )
        #expect(collected.count == 2)
        for type in [
            "NSPrivacyCollectedDataTypeAudioData",
            "NSPrivacyCollectedDataTypeOtherUserContent",
        ] {
            let entry = try manifestEntry(type, in: collected)
            #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == true)
            #expect(
                entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false
            )
            #expect(
                entry["NSPrivacyCollectedDataTypePurposes"] as? [String]
                    == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
            )
        }

        let accessed = try #require(
            app["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        #expect(accessed.count == 1)
        let fileTimestamp = try accessedAPIEntry(
            "NSPrivacyAccessedAPICategoryFileTimestamp",
            in: accessed
        )
        #expect(
            fileTimestamp["NSPrivacyAccessedAPITypeReasons"] as? [String]
                == ["C617.1"]
        )

        #expect(keyboard["NSPrivacyTracking"] as? Bool == false)
        #expect(
            (keyboard["NSPrivacyTrackingDomains"] as? [String])?.isEmpty
                == true
        )
        #expect(
            (keyboard["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty
                == true
        )
        #expect(
            (keyboard["NSPrivacyAccessedAPITypes"] as? [Any])?.isEmpty
                == true
        )
    }

    @Test func builtExecutableBundlesContainTheirPrivacyManifest() throws {
        let appManifest = try #require(
            Bundle.main.url(
                forResource: "PrivacyInfo",
                withExtension: "xcprivacy"
            )
        )
        _ = try plist(at: appManifest)

        let plugInsURL = try #require(Bundle.main.builtInPlugInsURL)
        let keyboardBundle = try #require(
            Bundle(
                url: plugInsURL.appendingPathComponent(
                    "HoldTypeKeyboard.appex",
                    isDirectory: true
                )
            )
        )
        let keyboardManifest = try #require(
            keyboardBundle.url(
                forResource: "PrivacyInfo",
                withExtension: "xcprivacy"
            )
        )
        _ = try plist(at: keyboardManifest)

        let exact = "HoldType uses the microphone to record speech you "
            + "choose to transcribe."
        #expect(
            Bundle.main.infoDictionary?["NSMicrophoneUsageDescription"]
                as? String == exact
        )
        #expect(
            keyboardBundle.infoDictionary?["NSMicrophoneUsageDescription"]
                == nil
        )
    }

    private func sourcePlist(at relativePath: String) throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try plist(at: repositoryRoot.appendingPathComponent(relativePath))
    }

    private func plist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try #require(plist as? [String: Any])
    }

    private func manifestEntry(
        _ type: String,
        in entries: [[String: Any]]
    ) throws -> [String: Any] {
        try #require(
            entries.first {
                $0["NSPrivacyCollectedDataType"] as? String == type
            }
        )
    }

    private func accessedAPIEntry(
        _ type: String,
        in entries: [[String: Any]]
    ) throws -> [String: Any] {
        try #require(
            entries.first {
                $0["NSPrivacyAccessedAPIType"] as? String == type
            }
        )
    }
}
