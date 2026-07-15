import Foundation
import Testing
@testable import HoldTypePersistence

struct IOSV1ProviderConsentTests {
    @Test func versionTwoAcceptanceRequiresReviewForDefaultAudioRetention()
        async throws {
        try await withFixture { fixture in
            let versionTwoRecord = Data(
                #"{"decision":"accepted","decisionAtMilliseconds":1800000000000,"disclosureVersion":2,"revision":1,"schemaVersion":1}"#.utf8
            )
            try FileManager.default.createDirectory(
                at: fixture.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try versionTwoRecord.write(to: fixture.fileURL)

            let observation = await fixture.coordinator.observe()

            #expect(
                IOSV1ProviderConsentCoordinator.currentDisclosureVersion == 3
            )
            #expect(observation.status == .reviewRequired)
            #expect(
                fixture.coordinator.makeAuthorization(from: observation) == nil
            )
        }
    }

    @Test func missingObserveIsPassiveAndAcceptanceSurvivesRestart() async throws {
        try await withFixture { fixture in
            let missing = await fixture.coordinator.observe()
            #expect(missing.status == .notReviewed)
            #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
            #expect(
                fixture.coordinator.makeAuthorization(from: missing) == nil
            )

            let accepted = try await fixture.coordinator.accept(
                using: missing,
                decisionAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
            #expect(accepted.status == .acceptedCurrentDisclosure)
            #expect(fixture.coordinator.isAuthorizationReady(for: accepted))
            #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))

            let restarted = IOSV1ProviderConsentCoordinator(
                fileURL: fixture.fileURL
            )
            let observed = await restarted.observe()
            #expect(observed.status == .acceptedCurrentDisclosure)
            #expect(restarted.isAuthorizationReady(for: observed))
            #expect(
                !restarted.hasSameObservationAuthority(observed, as: accepted)
            )
        }
    }

    @Test func staleObservationCannotOverwriteNewDecision() async throws {
        try await withFixture { fixture in
            let missing = await fixture.coordinator.observe()
            let accepted = try await fixture.coordinator.accept(
                using: missing,
                decisionAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
            await #expect(throws: IOSV1ProviderConsentError.staleObservation) {
                try await fixture.coordinator.accept(using: missing)
            }
            let withdrawn = try await fixture.coordinator.withdraw(
                using: accepted,
                decisionAt: Date(timeIntervalSince1970: 1_800_000_001)
            )
            #expect(withdrawn.status == .withdrawn)
            #expect(!fixture.coordinator.isAuthorizationReady(for: withdrawn))
        }
    }

    @Test func corruptRecordIsResettableButUnavailablePathIsNot() async throws {
        try await withFixture { fixture in
            try FileManager.default.createDirectory(
                at: fixture.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("{not-json".utf8).write(to: fixture.fileURL)
            let corrupt = await fixture.coordinator.observe()
            #expect(corrupt.status == .localDataUnavailable)
            #expect(corrupt.canResetUnreadableData)

            let reset = try await fixture.coordinator
                .resetUnreadableConsentData(using: corrupt)
            #expect(reset.status == .notReviewed)
            #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))

            try FileManager.default.createDirectory(
                at: fixture.fileURL,
                withIntermediateDirectories: false
            )
            let unavailableCoordinator = IOSV1ProviderConsentCoordinator(
                fileURL: fixture.fileURL
            )
            let unavailable = await unavailableCoordinator.observe()
            #expect(unavailable.status == .localDataUnavailable)
            #expect(!unavailable.canResetUnreadableData)
        }
    }

    @Test func withdrawalClosesAndCancelsBeforeCallback() async throws {
        try await withFixture { fixture in
            let accepted = try await acceptInitial(fixture.coordinator)
            let authorization = try #require(
                fixture.coordinator.makeAuthorization(from: accepted)
            )
            let cancellation = LockedConsentFlag()
            let registration = try #require(
                await fixture.coordinator.registerProviderDispatch(
                    authorization,
                    for: .transcription,
                    onCancellation: { cancellation.set() }
                )
            )
            let callbackObservedClose = LockedConsentFlag()

            let withdrawn = try await fixture.coordinator.withdraw(
                using: accepted,
                decisionAt: Date(timeIntervalSince1970: 1_800_000_001),
                authorizationDidClose: {
                    if cancellation.value,
                       fixture.coordinator.makeAuthorization(
                        from: accepted
                       ) == nil {
                        callbackObservedClose.set()
                    }
                }
            )

            #expect(withdrawn.status == .withdrawn)
            #expect(cancellation.value)
            #expect(callbackObservedClose.value)
            #expect(
                !(await fixture.coordinator.launchProviderDispatch(
                    registration,
                    launch: {}
                ))
            )
        }
    }

    @Test func launchIsLinearizedAndResultConsumptionIsOneShot() async throws {
        try await withFixture { fixture in
            let accepted = try await acceptInitial(fixture.coordinator)
            let authorization = try #require(
                fixture.coordinator.makeAuthorization(from: accepted)
            )
            let launched = LockedConsentFlag()
            let registration = try #require(
                await fixture.coordinator.registerProviderDispatch(
                    authorization,
                    for: .translation,
                    onCancellation: {}
                )
            )
            #expect(
                await fixture.coordinator.launchProviderDispatch(
                    registration,
                    launch: { launched.set() }
                )
            )
            #expect(launched.value)
            let result = try #require(
                await fixture.coordinator.finishProviderDispatch(
                    registration,
                    onResultCancellation: {}
                )
            )
            let consumed = await fixture.coordinator.consumeProviderResult(
                result,
                perform: { 7 }
            )
            #expect(consumed == 7)
            let duplicate = await fixture.coordinator.consumeProviderResult(
                result,
                perform: { 8 }
            )
            #expect(duplicate == nil)
        }
    }

    @Test func throwingConsumptionKeepsResultForRetry() async throws {
        try await withFixture { fixture in
            let accepted = try await acceptInitial(fixture.coordinator)
            let authorization = try #require(
                fixture.coordinator.makeAuthorization(from: accepted)
            )
            let registration = try #require(
                await fixture.coordinator.registerProviderDispatch(
                    authorization,
                    for: .correction,
                    onCancellation: {}
                )
            )
            #expect(
                await fixture.coordinator.launchProviderDispatch(
                    registration,
                    launch: {}
                )
            )
            let result = try #require(
                await fixture.coordinator.finishProviderDispatch(
                    registration,
                    onResultCancellation: {}
                )
            )
            await #expect(throws: ConsentTestError.expected) {
                _ = try await fixture.coordinator.consumeProviderResult(
                    result,
                    perform: { throw ConsentTestError.expected }
                ) as Int?
            }
            let retried = await fixture.coordinator.consumeProviderResult(
                result,
                perform: { 9 }
            )
            #expect(retried == 9)
        }
    }

    private func acceptInitial(
        _ coordinator: IOSV1ProviderConsentCoordinator
    ) async throws -> IOSV1ProviderConsentObservation {
        let missing = await coordinator.observe()
        return try await coordinator.accept(
            using: missing,
            decisionAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func withFixture(
        _ body: (ConsentFixture) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root
            .appendingPathComponent("HoldType", isDirectory: true)
            .appendingPathComponent("ios-v1-provider-consent.json")
        try await body(
            ConsentFixture(
                coordinator: IOSV1ProviderConsentCoordinator(fileURL: fileURL),
                fileURL: fileURL
            )
        )
    }
}

private struct ConsentFixture {
    let coordinator: IOSV1ProviderConsentCoordinator
    let fileURL: URL
}

private enum ConsentTestError: Error {
    case expected
}

private final class LockedConsentFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        lock.withLock { storedValue }
    }

    func set() {
        lock.withLock { storedValue = true }
    }
}
