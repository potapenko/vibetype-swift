import SwiftUI
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSContainingAppSceneHostTests {
    @Test func scenePhaseMappingIsExactAndFailClosed() {
        #expect(IOSVoiceSceneActivity(ScenePhase.active) == .active)
        #expect(IOSVoiceSceneActivity(ScenePhase.inactive) == .inactive)
        #expect(IOSVoiceSceneActivity(ScenePhase.background) == .background)
    }
}
