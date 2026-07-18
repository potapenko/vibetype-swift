import Foundation
import HoldTypeDomain
import Testing

struct VoiceAttemptOutcomeDomainIOSTests {
    @Test func publicAttemptOutcomeContractWorksThroughANormalIOSImport() {
        let outcomes: [VoiceAttemptOutcome] = [
            .resultReady,
            .recoverableFailure,
            .interrupted,
            .expired,
        ]

        #expect(outcomes.map(marker(for:)) == [0, 1, 2, 3])
        #expect(outcomes.allSatisfy { Mirror(reflecting: $0).children.isEmpty })
        requireSendable(VoiceAttemptOutcome.self)
        #expect(((outcomes[0] as Any) is any Encodable) == false)
        #expect(((outcomes[0] as Any) is any Decodable) == false)
        #expect(((outcomes[0] as Any) is any RawRepresentable) == false)
        #expect(((outcomes[0] as Any) is any Identifiable) == false)
        #expect(((outcomes[0] as Any) is any LocalizedError) == false)
        #expect(((outcomes[0] as Any) is any CustomStringConvertible) == false)
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
