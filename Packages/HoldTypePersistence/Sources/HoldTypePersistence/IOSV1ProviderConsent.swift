import Foundation

public enum IOSV1ProviderConsentStatus: Equatable, Sendable {
    case notReviewed
    case reviewRequired
    case acceptedCurrentDisclosure
    case withdrawn
    case localDataUnavailable
    case mutationNotSaved
}

public enum IOSV1ProviderConsentProviderStage: CaseIterable, Equatable, Sendable {
    case transcription
    case correction
    case translation
}

public enum IOSV1ProviderConsentError: Error, Equatable, Sendable {
    case staleObservation
    case unreadableDataRequiresReset
    case resetRequiresUnreadableObservation
    case revisionOverflow
    case localDataUnavailable
    case mutationNotSaved
}


struct IOSV1ProviderConsentObservationToken: Equatable, Sendable {
    let ownerID: UUID
    let source: IOSV1ProviderConsentSource
    let fenceGeneration: UUID
}

public struct IOSV1ProviderConsentObservation: Equatable, Sendable {
    public let status: IOSV1ProviderConsentStatus
    public let decisionAt: Date?
    public let canResetUnreadableData: Bool

    let token: IOSV1ProviderConsentObservationToken

    init(
        source: IOSV1ProviderConsentSource,
        token: IOSV1ProviderConsentObservationToken
    ) {
        self.token = token
        switch source {
        case .missing:
            status = .notReviewed
            decisionAt = nil
            canResetUnreadableData = false
        case .record(let record, _):
            if record.decision == .withdrawn {
                status = .withdrawn
            } else if record.disclosureVersion
                        == IOSV1ProviderConsentCoordinator.currentDisclosureVersion {
                status = .acceptedCurrentDisclosure
            } else {
                status = .reviewRequired
            }
            decisionAt = Date(
                timeIntervalSince1970:
                    Double(record.decisionAtMilliseconds) / 1_000
            )
            canResetUnreadableData = false
        case .unreadable:
            status = .localDataUnavailable
            decisionAt = nil
            canResetUnreadableData = true
        case .unavailable:
            status = .localDataUnavailable
            decisionAt = nil
            canResetUnreadableData = false
        }
    }

    public static func == (
        lhs: IOSV1ProviderConsentObservation,
        rhs: IOSV1ProviderConsentObservation
    ) -> Bool {
        lhs.status == rhs.status
            && lhs.decisionAt == rhs.decisionAt
            && lhs.canResetUnreadableData == rhs.canResetUnreadableData
            && lhs.token.ownerID == rhs.token.ownerID
            && lhs.token.source == rhs.token.source
    }
}

public struct IOSV1ProviderConsentAuthorization: Equatable, Sendable {
    fileprivate let fenceID: UUID
    fileprivate let generation: UUID
    fileprivate let source: IOSV1ProviderConsentSource
}

public struct IOSV1ProviderConsentDispatchRegistration: Equatable, Sendable {
    fileprivate let fenceID: UUID
    fileprivate let registrationID: UUID
    fileprivate let generation: UUID
    fileprivate let source: IOSV1ProviderConsentSource
    fileprivate let stage: IOSV1ProviderConsentProviderStage
}

public struct IOSV1ProviderConsentResultAuthorization: Equatable, Sendable {
    fileprivate let fenceID: UUID
    fileprivate let resultID: UUID
    fileprivate let generation: UUID
    fileprivate let source: IOSV1ProviderConsentSource
    fileprivate let stage: IOSV1ProviderConsentProviderStage
}

extension IOSV1ProviderConsentObservation: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSV1ProviderConsentObservation(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSV1ProviderConsentAuthorization: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSV1ProviderConsentAuthorization(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSV1ProviderConsentDispatchRegistration: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "IOSV1ProviderConsentDispatchRegistration(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension IOSV1ProviderConsentResultAuthorization: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "IOSV1ProviderConsentResultAuthorization(redacted)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}


final class IOSV1ProviderConsentFence: @unchecked Sendable {
    typealias Cancellation = @Sendable () -> Void

    struct MutationPermit: Equatable, Sendable {
        let identifier: UUID
    }

    private struct DispatchState: @unchecked Sendable {
        let registration: IOSV1ProviderConsentDispatchRegistration
        let cancellation: Cancellation
        var launched: Bool
    }

    private struct ResultState: @unchecked Sendable {
        let authorization: IOSV1ProviderConsentResultAuthorization
        let cancellation: Cancellation
    }

    private let lock = NSRecursiveLock()
    private let fenceID = UUID()
    private let ownerID = UUID()
    private var generation = UUID()
    private var source: IOSV1ProviderConsentSource?
    private var acceptedSource: IOSV1ProviderConsentSource?
    private var closedUntilExplicitAccept = false
    private var activeMutation: MutationPermit?
    private var dispatches: [UUID: DispatchState] = [:]
    private var results: [UUID: ResultState] = [:]

    func adoptPassive(
        _ newSource: IOSV1ProviderConsentSource
    ) -> (IOSV1ProviderConsentObservationToken, [Cancellation]) {
        lock.lock()
        defer { lock.unlock() }
        var cancellations: [Cancellation] = []
        if let source, source != newSource {
            cancellations = closeLocked(requireExplicitAccept: true)
        }
        source = newSource
        if newSource.acceptedCurrentDisclosure,
           !closedUntilExplicitAccept {
            acceptedSource = newSource
        } else if !newSource.acceptedCurrentDisclosure {
            acceptedSource = nil
        }
        return (tokenLocked(for: newSource), cancellations)
    }

    func beginMutation(
        using observation: IOSV1ProviderConsentObservation
    ) -> (MutationPermit, [Cancellation])? {
        lock.lock()
        defer { lock.unlock() }
        guard matchesLocked(observation.token) else { return nil }
        let permit = MutationPermit(identifier: UUID())
        activeMutation = permit
        let cancellations = closeLocked(requireExplicitAccept: true)
        return (permit, cancellations)
    }

    func completeMutation(
        _ permit: MutationPermit,
        source newSource: IOSV1ProviderConsentSource,
        opensAuthority: Bool
    ) -> IOSV1ProviderConsentObservationToken {
        lock.lock()
        defer { lock.unlock() }
        guard activeMutation == permit else {
            return tokenLocked(for: newSource)
        }
        activeMutation = nil
        source = newSource
        if opensAuthority && newSource.acceptedCurrentDisclosure {
            closedUntilExplicitAccept = false
            acceptedSource = newSource
        } else {
            acceptedSource = nil
        }
        return tokenLocked(for: newSource)
    }

    func makeAuthorization(
        from observation: IOSV1ProviderConsentObservation
    ) -> IOSV1ProviderConsentAuthorization? {
        lock.lock()
        defer { lock.unlock() }
        guard matchesLocked(observation.token),
              acceptedSource == observation.token.source else {
            return nil
        }
        return IOSV1ProviderConsentAuthorization(
            fenceID: fenceID,
            generation: generation,
            source: observation.token.source
        )
    }

    func isReady(
        _ observation: IOSV1ProviderConsentObservation
    ) -> Bool {
        makeAuthorization(from: observation) != nil
    }

    func hasSameAuthority(
        _ candidate: IOSV1ProviderConsentObservation,
        _ current: IOSV1ProviderConsentObservation
    ) -> Bool {
        candidate.token == current.token
    }

    func closeAuthorityUntilExplicitAcceptance() -> [Cancellation] {
        lock.lock()
        defer { lock.unlock() }
        return closeLocked(requireExplicitAccept: true)
    }

    func register(
        _ authorization: IOSV1ProviderConsentAuthorization,
        stage: IOSV1ProviderConsentProviderStage,
        cancellation: @escaping Cancellation
    ) -> IOSV1ProviderConsentDispatchRegistration? {
        lock.lock()
        defer { lock.unlock() }
        guard validatesLocked(authorization) else { return nil }
        let registration = IOSV1ProviderConsentDispatchRegistration(
            fenceID: fenceID,
            registrationID: UUID(),
            generation: generation,
            source: authorization.source,
            stage: stage
        )
        dispatches[registration.registrationID] = DispatchState(
            registration: registration,
            cancellation: cancellation,
            launched: false
        )
        return registration
    }

    func launch(
        _ registration: IOSV1ProviderConsentDispatchRegistration,
        operation: @Sendable () -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard validatesLocked(registration),
              var state = dispatches[registration.registrationID],
              state.registration == registration,
              !state.launched else {
            return false
        }
        state.launched = true
        dispatches[registration.registrationID] = state
        operation()
        return true
    }

    func cancel(
        _ registration: IOSV1ProviderConsentDispatchRegistration
    ) {
        let cancellation: Cancellation?
        lock.lock()
        if let state = dispatches.removeValue(
            forKey: registration.registrationID
        ), state.registration == registration {
            cancellation = state.cancellation
        } else {
            cancellation = nil
        }
        lock.unlock()
        cancellation?()
    }

    func finish(
        _ registration: IOSV1ProviderConsentDispatchRegistration,
        cancellation: @escaping Cancellation
    ) -> IOSV1ProviderConsentResultAuthorization? {
        lock.lock()
        defer { lock.unlock() }
        guard validatesLocked(registration),
              let dispatch = dispatches.removeValue(
                forKey: registration.registrationID
              ),
              dispatch.registration == registration,
              dispatch.launched else {
            return nil
        }
        let authorization = IOSV1ProviderConsentResultAuthorization(
            fenceID: fenceID,
            resultID: UUID(),
            generation: generation,
            source: registration.source,
            stage: registration.stage
        )
        results[authorization.resultID] = ResultState(
            authorization: authorization,
            cancellation: cancellation
        )
        return authorization
    }

    func consume<Value: Sendable>(
        _ authorization: IOSV1ProviderConsentResultAuthorization,
        operation: @Sendable () throws -> Value
    ) rethrows -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard validatesLocked(authorization),
              let state = results[authorization.resultID],
              state.authorization == authorization else {
            return nil
        }
        let value = try operation()
        results.removeValue(forKey: authorization.resultID)
        return value
    }

    func abandon(
        _ authorization: IOSV1ProviderConsentResultAuthorization
    ) {
        let cancellation: Cancellation?
        lock.lock()
        if let state = results.removeValue(forKey: authorization.resultID),
           state.authorization == authorization {
            cancellation = state.cancellation
        } else {
            cancellation = nil
        }
        lock.unlock()
        cancellation?()
    }

    private func closeLocked(
        requireExplicitAccept: Bool
    ) -> [Cancellation] {
        generation = UUID()
        acceptedSource = nil
        closedUntilExplicitAccept = requireExplicitAccept
        let cancellations = dispatches.values.map(\.cancellation)
            + results.values.map(\.cancellation)
        dispatches.removeAll()
        results.removeAll()
        return cancellations
    }

    private func tokenLocked(
        for source: IOSV1ProviderConsentSource
    ) -> IOSV1ProviderConsentObservationToken {
        IOSV1ProviderConsentObservationToken(
            ownerID: ownerID,
            source: source,
            fenceGeneration: generation
        )
    }

    private func matchesLocked(
        _ token: IOSV1ProviderConsentObservationToken
    ) -> Bool {
        token.ownerID == ownerID
            && token.source == source
            && token.fenceGeneration == generation
    }

    private func validatesLocked(
        _ authorization: IOSV1ProviderConsentAuthorization
    ) -> Bool {
        authorization.fenceID == fenceID
            && authorization.generation == generation
            && authorization.source == acceptedSource
    }

    private func validatesLocked(
        _ registration: IOSV1ProviderConsentDispatchRegistration
    ) -> Bool {
        registration.fenceID == fenceID
            && registration.generation == generation
            && registration.source == acceptedSource
    }

    private func validatesLocked(
        _ authorization: IOSV1ProviderConsentResultAuthorization
    ) -> Bool {
        authorization.fenceID == fenceID
            && authorization.generation == generation
            && authorization.source == acceptedSource
    }
}


#if DEBUG
/// Content-free observations used only by rendered-state qualification.
@_spi(HoldTypeIOSCore)
public enum IOSV1ProviderConsentQualificationFixture {
    private static let ownerID = UUID()
    private static let generation = UUID()

    public static func notReviewedObservation()
        -> IOSV1ProviderConsentObservation {
        observation(for: .missing)
    }

    public static func acceptedObservation()
        -> IOSV1ProviderConsentObservation {
        let record = IOSV1ProviderConsentRecord(
            revision: 1,
            disclosureVersion:
                IOSV1ProviderConsentCoordinator.currentDisclosureVersion,
            decision: .accepted,
            decisionAtMilliseconds: 1_767_225_600_000
        )
        let bytes = (try? IOSV1ProviderConsentWireCodec.encode(record))
            ?? Data()
        return observation(for: .record(record, bytes))
    }

    public static func resettableUnreadableObservation()
        -> IOSV1ProviderConsentObservation {
        observation(for: .unreadable(Data("invalid".utf8)))
    }

    public static func localDataUnavailableObservation()
        -> IOSV1ProviderConsentObservation {
        observation(for: .unavailable)
    }

    public static func isAuthorizationReady(
        for observation: IOSV1ProviderConsentObservation
    ) -> Bool {
        observation.status == .acceptedCurrentDisclosure
    }

    public static func hasSameObservationAuthority(
        _ candidate: IOSV1ProviderConsentObservation,
        as current: IOSV1ProviderConsentObservation
    ) -> Bool {
        candidate.token == current.token
    }

    private static func observation(
        for source: IOSV1ProviderConsentSource
    ) -> IOSV1ProviderConsentObservation {
        IOSV1ProviderConsentObservation(
            source: source,
            token: IOSV1ProviderConsentObservationToken(
                ownerID: ownerID,
                source: source,
                fenceGeneration: generation
            )
        )
    }
}
#endif
