import CoreGraphics
import Testing
@testable import HoldTypeIOS

struct IOSVoiceDraftViewportTests {
    @Test func focusPolicyChangesResponderOnlyWhenStateDiffers() {
        #expect(
            IOSVoiceDraftFocusPolicy.resolve(
                wantsFocus: true,
                isEditable: true,
                isFirstResponder: false
            ) == .becomeFirstResponder
        )
        #expect(
            IOSVoiceDraftFocusPolicy.resolve(
                wantsFocus: false,
                isEditable: true,
                isFirstResponder: true
            ) == .resignFirstResponder
        )
        #expect(
            IOSVoiceDraftFocusPolicy.resolve(
                wantsFocus: true,
                isEditable: false,
                isFirstResponder: true
            ) == .resignFirstResponder
        )
        #expect(
            IOSVoiceDraftFocusPolicy.resolve(
                wantsFocus: true,
                isEditable: true,
                isFirstResponder: true
            ) == .none
        )
        #expect(
            IOSVoiceDraftFocusPolicy.resolve(
                wantsFocus: false,
                isEditable: true,
                isFirstResponder: false
            ) == .none
        )
    }

    @Test func typographyUsesOneCompactStepThenKeepsReadableFloor() {
        #expect(
            IOSVoiceDraftTypographyPolicy.resolve(
                current: .large,
                largeContentHeight: 199,
                viewportHeight: 200,
                largeLineHeight: 24,
                usesAccessibilitySize: false
            ) == .large
        )
        #expect(
            IOSVoiceDraftTypographyPolicy.resolve(
                current: .large,
                largeContentHeight: 201,
                viewportHeight: 200,
                largeLineHeight: 24,
                usesAccessibilitySize: false
            ) == .compact
        )
        #expect(IOSVoiceDraftTypographyPolicy.compactPointSize == 18)
    }

    @Test func compactTypographyNeedsHeadroomBeforeReturningToLarge() {
        #expect(
            IOSVoiceDraftTypographyPolicy.resolve(
                current: .compact,
                largeContentHeight: 180,
                viewportHeight: 200,
                largeLineHeight: 20,
                usesAccessibilitySize: false
            ) == .compact
        )
        #expect(
            IOSVoiceDraftTypographyPolicy.resolve(
                current: .compact,
                largeContentHeight: 170,
                viewportHeight: 200,
                largeLineHeight: 20,
                usesAccessibilitySize: false
            ) == .large
        )
    }

    @Test func accessibilityTypographyNeverAutoShrinks() {
        #expect(
            IOSVoiceDraftTypographyPolicy.resolve(
                current: .compact,
                largeContentHeight: 800,
                viewportHeight: 200,
                largeLineHeight: 48,
                usesAccessibilitySize: true
            ) == .large
        )
    }

    @Test func appendFollowsOnlyWhileReaderRemainsAtTheEnd() {
        var state = IOSVoiceDraftFollowTailState()

        #expect(state.receive(.append, wasAtBottom: true) == .bottom)
        #expect(state.isFollowingTail)
        #expect(!state.hasUnseenAppend)

        state.userScrolled(isAtBottom: false)
        #expect(state.receive(.append, wasAtBottom: false) == .none)
        #expect(!state.isFollowingTail)
        #expect(state.hasUnseenAppend)

        state.userScrolled(isAtBottom: true)
        #expect(state.isFollowingTail)
        #expect(!state.hasUnseenAppend)
    }

    @Test func selectionSuspendsFollowUntilExplicitJump() {
        var state = IOSVoiceDraftFollowTailState()
        state.suspend()

        #expect(state.receive(.append, wasAtBottom: true) == .none)
        #expect(state.hasUnseenAppend)

        state.jumpToLatest()
        #expect(state.isFollowingTail)
        #expect(!state.hasUnseenAppend)
    }

    @Test func replacementStartsAtTopAndUndoPreservesPosition() {
        var state = IOSVoiceDraftFollowTailState()
        state.userScrolled(isAtBottom: false)

        #expect(state.receive(.replace, wasAtBottom: false) == .top)
        #expect(state.isFollowingTail)
        #expect(
            state.receive(.preservePosition, wasAtBottom: false) == .none
        )
    }
}
