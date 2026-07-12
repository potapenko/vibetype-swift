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

    private func sourcePlist(at relativePath: String) throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath)
        )
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try #require(plist as? [String: Any])
    }
}
