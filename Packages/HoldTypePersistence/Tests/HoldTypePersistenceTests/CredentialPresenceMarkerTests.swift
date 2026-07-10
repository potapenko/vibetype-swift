import Foundation
import Testing
@testable import HoldTypePersistence

struct CredentialPresenceMarkerTests {
    @Test func runtimeValueAllowsOnlyValidStateAndMutationCombinations() throws {
        let date = try fixtureDate()

        for state in [
            CredentialPresenceMarker.State.present,
            .absent,
            .unknown,
        ] {
            let marker = try CredentialPresenceMarker(state: state, updatedAt: date)
            #expect(marker.state == state)
            #expect(marker.updatedAt == date)
            #expect(marker.mutationKind == nil)
        }

        for mutationKind in [
            CredentialPresenceMarker.MutationKind.saveOrReplace,
            .remove,
        ] {
            let marker = try CredentialPresenceMarker(
                state: .mutationInProgress,
                updatedAt: date,
                mutationKind: mutationKind
            )
            #expect(marker.state == .mutationInProgress)
            #expect(marker.mutationKind == mutationKind)
        }

        #expect(throws: CredentialPresenceMarker.ValidationError.invalidMutationCombination) {
            _ = try CredentialPresenceMarker(
                state: .present,
                updatedAt: date,
                mutationKind: .saveOrReplace
            )
        }
        #expect(throws: CredentialPresenceMarker.ValidationError.invalidMutationCombination) {
            _ = try CredentialPresenceMarker(state: .mutationInProgress, updatedAt: date)
        }
    }

    @Test func runtimeValueIsEquatableAndSendableButNotCodable() throws {
        let date = try fixtureDate()
        let marker = try CredentialPresenceMarker(state: .present, updatedAt: date)

        #expect(marker == (try CredentialPresenceMarker(state: .present, updatedAt: date)))
        #expect(marker != (try CredentialPresenceMarker(state: .absent, updatedAt: date)))
        requireSendable(CredentialPresenceMarker.self)
        requireSendable(CredentialPresenceMarker.State.self)
        requireSendable(CredentialPresenceMarker.MutationKind.self)
        #expect(((marker as Any) is any Encodable) == false)
        #expect(((marker as Any) is any Decodable) == false)
        #expect(((marker.state as Any) is any Encodable) == false)
        #expect(((marker.mutationKind as Any) is any Encodable) == false)
    }

    @Test func savesAndLoadsEveryExactV1Fixture() throws {
        let date = try fixtureDate()
        let fixtures = [
            try Fixture(
                marker: CredentialPresenceMarker(state: .present, updatedAt: date),
                json: #"{"schemaVersion":1,"state":"present","updatedAt":"2026-07-10T12:34:56.000Z"}"#
            ),
            try Fixture(
                marker: CredentialPresenceMarker(state: .absent, updatedAt: date),
                json: #"{"schemaVersion":1,"state":"absent","updatedAt":"2026-07-10T12:34:56.000Z"}"#
            ),
            try Fixture(
                marker: CredentialPresenceMarker(state: .unknown, updatedAt: date),
                json: #"{"schemaVersion":1,"state":"unknown","updatedAt":"2026-07-10T12:34:56.000Z"}"#
            ),
            try Fixture(
                marker: CredentialPresenceMarker(
                    state: .mutationInProgress,
                    updatedAt: date,
                    mutationKind: .saveOrReplace
                ),
                json: #"{"mutationKind":"saveOrReplace","schemaVersion":1,"state":"mutationInProgress","updatedAt":"2026-07-10T12:34:56.000Z"}"#
            ),
            try Fixture(
                marker: CredentialPresenceMarker(
                    state: .mutationInProgress,
                    updatedAt: date,
                    mutationKind: .remove
                ),
                json: #"{"mutationKind":"remove","schemaVersion":1,"state":"mutationInProgress","updatedAt":"2026-07-10T12:34:56.000Z"}"#
            ),
        ]

        for fixture in fixtures {
            let fileSystem = CredentialMarkerFileSystemFake()
            let repository = makeRepository(fileSystem: fileSystem)

            try repository.save(fixture.marker)
            #expect(fileSystem.data == fixture.data)
            #expect(try repository.load() == fixture.marker)

            fileSystem.data = fixture.data
            #expect(try repository.load() == fixture.marker)
        }
    }

    @Test func missingMarkerDoesNotMeanAbsent() throws {
        let fileSystem = CredentialMarkerFileSystemFake(data: nil)
        let repository = makeRepository(fileSystem: fileSystem)

        #expect(try repository.load() == nil)
        #expect(fileSystem.replacementCallCount == 0)
    }

    @Test func invalidSourcesReturnTypedErrorsAndStayByteForByteUnchanged() throws {
        let cases: [(String, CredentialPresenceMarkerRepositoryError)] = [
            ("not-json", .corruptData),
            (
                #"{"schemaVersion":2,"state":"present","updatedAt":"2026-07-10T12:34:56.000Z"}"#,
                .unsupportedSchemaVersion(2)
            ),
            (
                #"{"schemaVersion":1,"state":"futureState","updatedAt":"2026-07-10T12:34:56.000Z"}"#,
                .invalidState("futureState")
            ),
            (
                #"{"mutationKind":"futureMutation","schemaVersion":1,"state":"mutationInProgress","updatedAt":"2026-07-10T12:34:56.000Z"}"#,
                .invalidMutationKind("futureMutation")
            ),
            (
                #"{"schemaVersion":1,"state":"mutationInProgress","updatedAt":"2026-07-10T12:34:56.000Z"}"#,
                .invalidMutationCombination
            ),
            (
                #"{"mutationKind":"remove","schemaVersion":1,"state":"present","updatedAt":"2026-07-10T12:34:56.000Z"}"#,
                .invalidMutationCombination
            ),
            (
                #"{"mutationKind":null,"schemaVersion":1,"state":"present","updatedAt":"2026-07-10T12:34:56.000Z"}"#,
                .invalidMutationCombination
            ),
            (
                #"{"schemaVersion":1,"state":"present","updatedAt":"not-a-date"}"#,
                .corruptData
            ),
            (
                #"{"providerStatus":"accepted","schemaVersion":1,"state":"present","updatedAt":"2026-07-10T12:34:56.000Z"}"#,
                .unexpectedFields(["providerStatus"])
            ),
            (
                #"{"schemaVersion":0,"state":"present","updatedAt":"2026-07-10T12:34:56.000Z"}"#,
                .unsupportedSchemaVersion(0)
            ),
        ]

        for (json, expectedError) in cases {
            let originalData = Data(json.utf8)
            let fileSystem = CredentialMarkerFileSystemFake(data: originalData)
            let repository = makeRepository(fileSystem: fileSystem)

            #expect(throws: expectedError) {
                _ = try repository.load()
            }
            #expect(fileSystem.data == originalData)
            #expect(fileSystem.replacementCallCount == 0)
        }
    }

    @Test func failedAtomicReplacementPreservesPreviousBytes() throws {
        let previousData = Data("previous-marker-bytes".utf8)
        let fileSystem = CredentialMarkerFileSystemFake(
            data: previousData,
            replacementError: CredentialMarkerFileSystemFakeError.replacementFailed
        )
        let repository = makeRepository(fileSystem: fileSystem)
        let marker = try CredentialPresenceMarker(
            state: .present,
            updatedAt: fixtureDate()
        )

        #expect(throws: CredentialPresenceMarkerRepositoryError.writeFailed) {
            try repository.save(marker)
        }
        #expect(fileSystem.data == previousData)
        #expect(fileSystem.replacementCallCount == 1)
    }

    @Test func everyReplacementRequestsCompleteProtectionAndBackupExclusion() throws {
        let fileSystem = CredentialMarkerFileSystemFake()
        let repository = makeRepository(fileSystem: fileSystem)

        try repository.save(
            CredentialPresenceMarker(state: .present, updatedAt: fixtureDate())
        )
        try repository.save(
            CredentialPresenceMarker(state: .absent, updatedAt: fixtureDate())
        )

        #expect(fileSystem.replacementOptions.count == 2)
        #expect(fileSystem.replacementOptions.allSatisfy {
            $0.fileProtection == .complete && $0.excludesFromBackup
        })
    }

    @Test func encodedV1UsesOnlyAllowlistedNonSecretFields() throws {
        let fileSystem = CredentialMarkerFileSystemFake()
        let repository = makeRepository(fileSystem: fileSystem)
        let marker = try CredentialPresenceMarker(
            state: .mutationInProgress,
            updatedAt: fixtureDate(),
            mutationKind: .saveOrReplace
        )

        try repository.save(marker)
        let data = try #require(fileSystem.data)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(Set(object.keys) == [
            "schemaVersion",
            "state",
            "updatedAt",
            "mutationKind",
        ])

        let forbiddenSentinels = [
            "apiKey",
            "maskedKey",
            "keychain",
            "service",
            "account",
            "provider",
            "appGroup",
            "keyboard",
        ]
        let persistedText = String(decoding: data, as: UTF8.self).lowercased()
        for sentinel in forbiddenSentinels {
            #expect(!persistedText.contains(sentinel.lowercased()))
        }
    }

    @Test func readFailuresUseThePublicTypedError() {
        let fileSystem = CredentialMarkerFileSystemFake(
            readError: CredentialMarkerFileSystemFakeError.readFailed
        )
        let repository = makeRepository(fileSystem: fileSystem)

        #expect(throws: CredentialPresenceMarkerRepositoryError.readFailed) {
            _ = try repository.load()
        }
        #expect(fileSystem.replacementCallCount == 0)
    }

    private func makeRepository(
        fileSystem: CredentialMarkerFileSystemFake
    ) -> CredentialPresenceMarkerRepository {
        CredentialPresenceMarkerRepository(
            fileURL: URL(fileURLWithPath: "/app-private/credential-presence-v1.json"),
            fileSystem: fileSystem
        )
    }

    private func fixtureDate() throws -> Date {
        try #require(
            ISO8601DateFormatter.fixtureFormatter.date(from: "2026-07-10T12:34:56.000Z")
        )
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}

private struct Fixture {
    let marker: CredentialPresenceMarker
    let data: Data

    init(marker: CredentialPresenceMarker, json: String) throws {
        self.marker = marker
        self.data = Data(json.utf8)
    }
}

private enum CredentialMarkerFileSystemFakeError: Error {
    case readFailed
    case replacementFailed
}

private final class CredentialMarkerFileSystemFake: CredentialPresenceMarkerFileSystem {
    var data: Data?
    var replacementCallCount = 0
    var replacementOptions: [CredentialPresenceMarkerReplacementOptions] = []
    var readError: Error?
    var replacementError: Error?

    init(
        data: Data? = nil,
        readError: Error? = nil,
        replacementError: Error? = nil
    ) {
        self.data = data
        self.readError = readError
        self.replacementError = replacementError
    }

    func readFileIfPresent(at fileURL: URL) throws -> Data? {
        if let readError {
            throw readError
        }
        return data
    }

    func replaceFileAtomically(
        at fileURL: URL,
        with data: Data,
        options: CredentialPresenceMarkerReplacementOptions
    ) throws {
        replacementCallCount += 1
        replacementOptions.append(options)
        if let replacementError {
            throw replacementError
        }
        self.data = data
    }
}

private extension ISO8601DateFormatter {
    static var fixtureFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
