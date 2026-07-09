import HoldTypeDomain
import Testing
@testable import HoldType

struct DictationOutputIntentTests {
    @Test func macOSHotkeyPromotionMergeKeepsTranslateSticky() {
        #expect(DictationOutputIntent.standard.merged(with: .standard) == .standard)
        #expect(DictationOutputIntent.standard.merged(with: .translate) == .translate)
        #expect(DictationOutputIntent.translate.merged(with: .standard) == .translate)
        #expect(DictationOutputIntent.translate.merged(with: .translate) == .translate)
    }
}
