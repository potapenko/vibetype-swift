import Foundation
import HoldTypePersistence
import Testing

struct CredentialPresenceMarkerPersistenceIOSTests {
    @Test func publicRepositoryReportsFailedReplacementWithoutChangingTheBlockingSource() throws {
        let directoryURL = makeTemporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let blockingURL = directoryURL.appendingPathComponent("not-a-directory")
        let blockingBytes = Data("blocking-source".utf8)
        try blockingBytes.write(to: blockingURL)
        let repository = CredentialPresenceMarkerRepository(
            fileURL: blockingURL.appendingPathComponent("credential-presence-v1.json")
        )
        let marker = try CredentialPresenceMarker(
            state: .present,
            updatedAt: fixtureDate()
        )

        #expect(throws: CredentialPresenceMarkerRepositoryError.writeFailed) {
            try repository.save(marker)
        }
        #expect(try Data(contentsOf: blockingURL) == blockingBytes)
    }

    @Test func oversizedAndNonRegularSourcesAreRejectedWithoutChangingThem() throws {
        let directoryURL = makeTemporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = directoryURL.appendingPathComponent("credential-presence-v1.json")
        let oversizedData = Data(repeating: 0x61, count: 16 * 1_024 + 1)
        try oversizedData.write(to: fileURL)
        let repository = CredentialPresenceMarkerRepository(fileURL: fileURL)

        #expect(throws: CredentialPresenceMarkerRepositoryError.storageLimitExceeded) {
            _ = try repository.load()
        }
        #expect(try Data(contentsOf: fileURL) == oversizedData)

        try FileManager.default.removeItem(at: fileURL)
        let sentinelURL = directoryURL.appendingPathComponent("sentinel")
        try Data("sentinel".utf8).write(to: sentinelURL)
        try FileManager.default.createSymbolicLink(
            at: fileURL,
            withDestinationURL: sentinelURL
        )
        #expect(throws: CredentialPresenceMarkerRepositoryError.readFailed) {
            _ = try repository.load()
        }
        #expect(try Data(contentsOf: sentinelURL) == Data("sentinel".utf8))
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path) ==
                sentinelURL.path
        )
    }

    private func makeTemporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-credential-marker-tests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func fixtureDate() throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try #require(
            formatter.date(from: "2026-07-10T12:34:56.000Z")
        )
    }
}
