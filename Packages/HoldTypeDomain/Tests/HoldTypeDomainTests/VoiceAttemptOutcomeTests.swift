import Foundation
import Testing
@testable import HoldTypeDomain

struct VoiceAttemptOutcomeTests {
    @Test func representsExactlyTheFourTerminalAttemptOutcomes() {
        let outcomes: [VoiceAttemptOutcome] = [
            .resultReady,
            .recoverableFailure,
            .interrupted,
            .expired,
        ]

        #expect(outcomes.map(marker(for:)) == [0, 1, 2, 3])
        for leftIndex in outcomes.indices {
            for rightIndex in outcomes.indices {
                #expect((outcomes[leftIndex] == outcomes[rightIndex]) == (leftIndex == rightIndex))
            }
        }
        #expect(outcomes.allSatisfy { Mirror(reflecting: $0).children.isEmpty })
    }

    @Test func publicValueIsSendableButNotATransportContract() {
        requireSendable(VoiceAttemptOutcome.self)
        let outcome = VoiceAttemptOutcome.resultReady

        #expect(((outcome as Any) is any Encodable) == false)
        #expect(((outcome as Any) is any Decodable) == false)
        #expect(((outcome as Any) is any RawRepresentable) == false)
        #expect(((outcome as Any) is any Identifiable) == false)
        #expect(((outcome as Any) is any LocalizedError) == false)
        #expect(((outcome as Any) is any CustomStringConvertible) == false)
    }

    @Test func remainsIndependentFromWorkPhaseAndStage() {
        let phase = VoiceWorkPhase.inactive
        let stage = VoiceAttemptStage.outputDelivery
        let outcome = VoiceAttemptOutcome.resultReady

        #expect(phase == .inactive)
        #expect(stage == .outputDelivery)
        #expect(outcome == .resultReady)
        #expect(VoiceAttemptOutcome.expired == .expired)
    }

    private func marker(for outcome: VoiceAttemptOutcome) -> Int {
        switch outcome {
        case .resultReady:
            return 0
        case .recoverableFailure:
            return 1
        case .interrupted:
            return 2
        case .expired:
            return 3
        }
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
