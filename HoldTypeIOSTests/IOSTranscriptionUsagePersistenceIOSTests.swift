import Foundation
import HoldTypeDomain
import HoldTypePersistence
import Testing

struct IOSTranscriptionUsagePersistenceIOSTests {
    @Test func publicRepositoryPersistsProtectedBackupExcludedUsageOnIOS() async throws {
        let containerURL = makeTemporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let applicationSupportURL = containerURL.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        let fileURL = applicationSupportURL
            .appendingPathComponent("HoldType", isDirectory: true)
            .appendingPathComponent("ios-transcription-usage.json")
        #expect(
            IOSTranscriptionUsageStorageLocation.fileURL(in: applicationSupportURL) ==
                fileURL
        )

        let repository = IOSTranscriptionUsageRepository(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        #expect(try await repository.load().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        let identifier = try #require(
            UUID(uuidString: "C0000000-0000-0000-0000-000000000000")
        )
        let usage = try SuccessfulTranscriptionUsage(
            transcriptionID: identifier,
            model: " GPT-4O-Transcribe ",
            audioDuration: 120
        )
        #expect(try await repository.record(usage) == .inserted)
        #expect(try await repository.record(usage) == .duplicate)

        let events = try await repository.load()
        let event = try #require(events.first)
        #expect(events.count == 1)
        #expect(event.id == identifier)
        #expect(event.model == "gpt-4o-transcribe")
        #expect(event.durationSeconds == 120)
        #expect(event.priceUSDPerMinute == 0.006)
        #expect(event.estimatedCostUSD == 0.012)
        #expect(event.pricingSource == "OpenAI pricing reviewed 2026-06-22")
        requireSendable(TranscriptionUsageEvent.self)
        requireSendable(TranscriptionUsagePricing.self)
        #expect(((event as Any) is any Encodable) == false)
        #expect(((event as Any) is any Decodable) == false)

        #expect(
            try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #if targetEnvironment(simulator)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }
        #else
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
        #endif

        let storedText = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
        for forbidden in [
            "transcript", "prompt", "audio", "credential", "authorization",
            "providerPayload", "apiKey",
        ] {
            #expect(!storedText.lowercased().contains(forbidden.lowercased()))
        }

        try await repository.reset()
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        try await repository.reset()
    }

    private func makeTemporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-ios-usage-tests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
