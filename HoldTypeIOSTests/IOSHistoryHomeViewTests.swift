import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypeIOS

@MainActor
struct IOSHistoryHomeViewTests {
    @Test func copyWritesTheExactSelectedTextOnce() {
        var copiedTexts: [String] = []
        let actions = IOSHistoryRowActions(
            copyText: { copiedTexts.append($0) }
        )
        let text = "  Exact text\nwith emoji 🫡 and punctuation!?  "

        actions.copy(text)

        #expect(copiedTexts == [text])
    }

    @Test func asyncPlaybackBoundaryUsesOnlyResolvedCacheEntries() async {
        let playableID = UUID()
        let missingID = UUID()
        var resolvedIDs: [[UUID]] = []
        var playedIDs: [UUID] = []
        let actions = IOSHistoryPlaybackActions(
            resolvePlayableResultIDs: { resultIDs in
                resolvedIDs.append(resultIDs)
                return [playableID]
            },
            playRecording: { resultID in
                playedIDs.append(resultID)
                return resultID == playableID ? .played : .unavailable
            }
        )

        let playable = await actions.playableResultIDs([
            playableID,
            missingID,
        ])
        let played = await actions.play(resultID: playableID)
        let unavailable = await actions.play(resultID: missingID)

        #expect(resolvedIDs == [[playableID, missingID]])
        #expect(playable == [playableID])
        #expect(played == .played)
        #expect(unavailable == .unavailable)
        #expect(playedIDs == [playableID, missingID])
    }

    @Test func cachePolicyReconciliationIsExplicitAndNormalized() async {
        var reconciledPolicies: [RecordingCachePolicy] = []
        var stopCount = 0
        let actions = IOSHistoryPlaybackActions(
            resolvePlayableResultIDs: { _ in [] },
            playRecording: { _ in .failed },
            stopPlayback: { stopCount += 1 },
            reconcileCache: { policy in
                reconciledPolicies.append(policy)
                return true
            }
        )

        #expect(await actions.reconcile(policy: .keepLast(0)))
        await actions.stop()

        #expect(reconciledPolicies == [.keepLast(1)])
        #expect(stopCount == 1)
    }
}
