import Foundation

/// A non-secret, last-known credential status owned only by the containing app.
public struct CredentialPresenceMarker: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case present
        case absent
        case unknown
        case mutationInProgress
    }

    public enum MutationKind: Equatable, Sendable {
        case saveOrReplace
        case remove
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidMutationCombination
    }

    public let state: State
    public let updatedAt: Date
    public let mutationKind: MutationKind?

    public init(
        state: State,
        updatedAt: Date,
        mutationKind: MutationKind? = nil
    ) throws {
        switch (state, mutationKind) {
        case (.mutationInProgress, .some),
             (.present, .none),
             (.absent, .none),
             (.unknown, .none):
            break
        default:
            throw ValidationError.invalidMutationCombination
        }

        self.state = state
        self.updatedAt = updatedAt
        self.mutationKind = mutationKind
    }
}
