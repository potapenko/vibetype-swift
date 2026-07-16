#if DEBUG
import Testing
@testable import HoldTypeIOS

struct IOSKeyboardHandoffSheetTests {
    @Test func startingPresentationDoesNotClaimListening() {
        let presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .starting
        )

        #expect(presentation.title == "Starting dictation…")
        #expect(presentation.detail == "Getting your microphone ready.")
        #expect(presentation.activityPhase == .ready)
        #expect(!presentation.returnInstructionIsActive)
        #expect(!presentation.accessibilityStatus.contains("is listening"))
    }

    @Test func listeningPresentationActivatesTheReturnInstruction() {
        let presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .listening
        )

        #expect(presentation.title == "HoldType is listening")
        #expect(
            presentation.instructionTitle
                == "Swipe right to return"
        )
        #expect(
            presentation.instructionDetail
                == "Recording will continue after you return."
        )
        #expect(presentation.activityPhase == .listening)
        #expect(presentation.returnInstructionIsActive)
    }

    @Test func qualificationRoutesExposeBothDeterministicSheetStates() {
        #expect(
            IOSUIQualificationRoute.keyboardHandoffStarting.rawValue
                == "keyboard-handoff-starting"
        )
        #expect(
            IOSUIQualificationRoute.keyboardHandoffListening.rawValue
                == "keyboard-handoff-listening"
        )
    }

    @Test func blockedPresentationContainsRecoveryInsideTheSheet() {
        let presentation = IOSKeyboardHandoffSheetPresentation(
            issue: .providerConsent
        )

        #expect(presentation.phase == .blocked)
        #expect(presentation.title == "Review OpenAI processing")
        #expect(presentation.detail.contains("disclosure"))
        #expect(presentation.activityPhase == nil)
        #expect(!presentation.showsReturnInstruction)
        #expect(!presentation.returnInstructionIsActive)
    }

    @Test func processingPresentationKeepsTheSheetAsTerminalOwner() {
        let presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .processing
        )

        #expect(presentation.title == "Processing dictation…")
        #expect(presentation.activityPhase == .recognizing)
        #expect(!presentation.showsReturnInstruction)
        #expect(!presentation.returnInstructionIsActive)
    }

    @Test func reduceMotionDisablesTheAnimatedReturnCue() {
        #expect(
            IOSKeyboardHandoffMotionPolicy.animatesReturnCue(
                isActive: true,
                reduceMotion: false
            )
        )
        #expect(
            !IOSKeyboardHandoffMotionPolicy.animatesReturnCue(
                isActive: true,
                reduceMotion: true
            )
        )
        #expect(
            !IOSKeyboardHandoffMotionPolicy.animatesReturnCue(
                isActive: false,
                reduceMotion: false
            )
        )
    }
}
#endif
