#if DEBUG
import Foundation
@_spi(HoldTypeIOSCore) import HoldTypePersistence
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSKeyboardHandoffSheetTests {
    @Test func startingPresentationDoesNotClaimListening() {
        let presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .starting
        )

        #expect(presentation.title == "Starting dictation…")
        #expect(presentation.detail == "Getting your microphone ready.")
        #expect(presentation.activityPhase == .ready)
        #expect(!presentation.returnInstructionIsActive)
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

    @Test func savedRecordingPresentationOwnsRecoveryInsideTheSheet() {
        let presentation = IOSKeyboardHandoffSheetPresentation(
            phase: .savedRecording
        )

        #expect(presentation.title == "Recording Saved")
        #expect(presentation.activityPhase == nil)
        #expect(!presentation.showsReturnInstruction)
        #expect(!presentation.returnInstructionIsActive)
    }

    @Test func failedSavedRecordingOffersPlayRetryAndDelete() throws {
        let resolvedCard = try savedRecordingCard(phase: .failed)
        let card = try #require(resolvedCard)

        let content = IOSKeyboardHandoffSavedRecordingContent(card: card)

        #expect(content.title == "Recording Saved")
        #expect(content.showsPlay)
        #expect(content.primaryActionTitle == "Retry")
        #expect(content.allowsDelete)
        #expect(content.durationText == "0:30")
    }

    @Test func readyAndProcessingSavedRecordingActionsStayTruthful()
        throws {
        let resolvedReadyCard = try savedRecordingCard(
            phase: .readyForTranscription
        )
        let ready = IOSKeyboardHandoffSavedRecordingContent(
            card: try #require(resolvedReadyCard)
        )
        #expect(ready.title == "Ready to Transcribe")
        #expect(ready.primaryActionTitle == "Transcribe")
        #expect(ready.allowsDelete)

        let resolvedProcessingCard = try savedRecordingCard(
            phase: .transcribing,
            transcriptionID: UUID()
        )
        let processing = IOSKeyboardHandoffSavedRecordingContent(
            card: try #require(resolvedProcessingCard)
        )
        #expect(processing.showsPlay)
        #expect(processing.primaryActionTitle == nil)
        #expect(!processing.allowsDelete)
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

@MainActor
private func savedRecordingCard(
    phase: IOSV1PendingRecordingPhase,
    transcriptionID: UUID? = nil
) throws -> IOSPendingRecordingHistoryCard? {
    IOSPendingRecordingHistoryStateOwner.resolve(
        .pending(
            IOSV1PendingRecordingObservation(
                recording: try IOSV1PendingRecording.qualificationFixture(
                    phase: phase,
                    transcriptionID: transcriptionID,
                    durationMilliseconds: 30_000,
                    byteCount: 4_096
                ),
                availability: .available
            )
        ),
        supportsPlayback: true
    ).card
}
#endif
