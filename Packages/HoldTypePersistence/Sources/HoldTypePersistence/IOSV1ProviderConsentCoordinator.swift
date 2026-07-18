import Foundation

public final class IOSV1ProviderConsentCoordinator: @unchecked Sendable {
    public static let currentDisclosureVersion: Int64 = 3

    private let repository: IOSV1ProviderConsentRepository
    private let fence = IOSV1ProviderConsentFence()

    @_spi(HoldTypeIOSCore)
    public convenience init(applicationSupportDirectoryURL: URL) {
        self.init(
            fileURL: applicationSupportDirectoryURL
                .appendingPathComponent("HoldType", isDirectory: true)
                .appendingPathComponent(
                    "ios-v1-provider-consent.json",
                    isDirectory: false
                )
        )
    }

    init(
        fileURL: URL,
        fileSystem: any ProtectedAtomicMetadataFileSystem =
            FoundationProtectedAtomicMetadataFileSystem()
    ) {
        repository = IOSV1ProviderConsentRepository(
            fileURL: fileURL,
            fileSystem: fileSystem
        )
    }

    public func observe() async -> IOSV1ProviderConsentObservation {
        let source = await repository.observe()
        let (token, cancellations) = fence.adoptPassive(source)
        cancellations.forEach { $0() }
        return IOSV1ProviderConsentObservation(source: source, token: token)
    }

    public func accept(
        using observation: IOSV1ProviderConsentObservation,
        decisionAt: Date = Date()
    ) async throws -> IOSV1ProviderConsentObservation {
        guard let (permit, cancellations) = fence.beginMutation(
            using: observation
        ) else {
            throw IOSV1ProviderConsentError.staleObservation
        }
        cancellations.forEach { $0() }
        let source = try await repository.accept(
            expected: observation.token.source,
            decisionAt: decisionAt
        )
        let token = fence.completeMutation(
            permit,
            source: source,
            opensAuthority: true
        )
        return IOSV1ProviderConsentObservation(source: source, token: token)
    }

    public func withdraw(
        using observation: IOSV1ProviderConsentObservation,
        decisionAt: Date = Date(),
        authorizationDidClose: @escaping @Sendable () async -> Void = {}
    ) async throws -> IOSV1ProviderConsentObservation {
        guard let (permit, cancellations) = fence.beginMutation(
            using: observation
        ) else {
            throw IOSV1ProviderConsentError.staleObservation
        }
        cancellations.forEach { $0() }
        await authorizationDidClose()
        let source = try await repository.withdraw(
            expected: observation.token.source,
            decisionAt: decisionAt
        )
        let token = fence.completeMutation(
            permit,
            source: source,
            opensAuthority: false
        )
        return IOSV1ProviderConsentObservation(source: source, token: token)
    }

    public func resetUnreadableConsentData(
        using observation: IOSV1ProviderConsentObservation,
        authorizationDidClose: @escaping @Sendable () async -> Void = {}
    ) async throws -> IOSV1ProviderConsentObservation {
        guard let (permit, cancellations) = fence.beginMutation(
            using: observation
        ) else {
            throw IOSV1ProviderConsentError.staleObservation
        }
        cancellations.forEach { $0() }
        await authorizationDidClose()
        let source = try await repository.resetUnreadable(
            expected: observation.token.source
        )
        let token = fence.completeMutation(
            permit,
            source: source,
            opensAuthority: false
        )
        return IOSV1ProviderConsentObservation(source: source, token: token)
    }

    public func makeAuthorization(
        from observation: IOSV1ProviderConsentObservation
    ) -> IOSV1ProviderConsentAuthorization? {
        fence.makeAuthorization(from: observation)
    }

    public func isAuthorizationReady(
        for observation: IOSV1ProviderConsentObservation
    ) -> Bool {
        fence.isReady(observation)
    }

    public func hasSameObservationAuthority(
        _ candidate: IOSV1ProviderConsentObservation,
        as current: IOSV1ProviderConsentObservation
    ) -> Bool {
        fence.hasSameAuthority(candidate, current)
    }

    @_spi(HoldTypeIOSCore)
    public func closeProviderAuthorizations() {
        fence.closeAuthorityUntilExplicitAcceptance().forEach { $0() }
    }

    public func registerProviderDispatch(
        _ authorization: IOSV1ProviderConsentAuthorization,
        for stage: IOSV1ProviderConsentProviderStage,
        onCancellation: @escaping @Sendable () -> Void
    ) async -> IOSV1ProviderConsentDispatchRegistration? {
        fence.register(
            authorization,
            stage: stage,
            cancellation: onCancellation
        )
    }

    public func launchProviderDispatch(
        _ registration: IOSV1ProviderConsentDispatchRegistration,
        launch: @Sendable () -> Void
    ) async -> Bool {
        fence.launch(registration, operation: launch)
    }

    public func cancelProviderDispatch(
        _ registration: IOSV1ProviderConsentDispatchRegistration
    ) {
        fence.cancel(registration)
    }

    public func finishProviderDispatch(
        _ registration: IOSV1ProviderConsentDispatchRegistration,
        onResultCancellation: @escaping @Sendable () -> Void
    ) async -> IOSV1ProviderConsentResultAuthorization? {
        fence.finish(registration, cancellation: onResultCancellation)
    }

    public func consumeProviderResult<Value: Sendable>(
        _ authorization: IOSV1ProviderConsentResultAuthorization,
        perform operation: @Sendable () throws -> Value
    ) async rethrows -> Value? {
        try fence.consume(authorization, operation: operation)
    }

    public func abandonProviderResult(
        _ authorization: IOSV1ProviderConsentResultAuthorization
    ) {
        fence.abandon(authorization)
    }
}

extension IOSV1ProviderConsentCoordinator: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "IOSV1ProviderConsentCoordinator(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [:]) }
}
