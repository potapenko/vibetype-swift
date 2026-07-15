import Foundation
import HoldTypeDomain
import HoldTypePersistence
import Testing

struct IOSAppSettingsPersistenceIOSTests {
    @Test func publicRuntimeContractWorksThroughNormalIOSImports() {
        let settings = IOSAppSettings.defaults

        #expect(settings.transcriptionConfiguration == .defaults)
        #expect(settings.textCorrectionConfiguration == .defaults)
        #expect(settings.localTextCleanupEnabled)
        #expect(settings.translationConfiguration == .defaults)
        #expect(settings.voiceSessionPreferences == .defaults)
        #expect(settings.recordingCachePolicy == .keepLast(20))
        requireSendable(IOSAppSettings.self)
        #expect(((settings as Any) is any Encodable) == false)
        #expect(((settings as Any) is any Decodable) == false)
    }

    @Test func publicRepositoryUsesStableLocationAndProtectedBackupEligibleFiles() async throws {
        let containerURL = makeTemporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let applicationSupportURL = containerURL.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        let expectedFileURL = applicationSupportURL
            .appendingPathComponent("HoldType", isDirectory: true)
            .appendingPathComponent("ios-app-settings.json", isDirectory: false)
        #expect(
            IOSAppSettingsStorageLocation.fileURL(in: applicationSupportURL) ==
                expectedFileURL
        )

        let repository = IOSAppSettingsRepository(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        #expect(try await repository.load() == .defaults)
        #expect(!FileManager.default.fileExists(atPath: expectedFileURL.path))

        let settings = fixtureSettings()
        try await repository.save(settings)
        #expect(try await repository.load() == settings)
        #expect(FileManager.default.fileExists(atPath: expectedFileURL.path))
        #expect(
            try expectedFileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == false
        )

        let attributes = try FileManager.default.attributesOfItem(
            atPath: expectedFileURL.path
        )
        #if targetEnvironment(simulator)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }
        #else
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
        #endif
    }

    @Test func unsupportedOrCorruptSourceBytesArePreserved() async throws {
        let containerURL = makeTemporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let applicationSupportURL = containerURL.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        let fileURL = IOSAppSettingsStorageLocation.fileURL(in: applicationSupportURL)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let repository = IOSAppSettingsRepository(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let fixtures: [(Data, IOSAppSettingsRepositoryError)] = [
            (Data("not-json".utf8), .malformedData),
            (
                Data(#"{"schemaVersion":2}"#.utf8),
                .unsupportedSchemaVersion
            ),
            (
                Data(#"{"schemaVersion":1,"voice":{"audioCuesEnabled":null}}"#.utf8),
                .invalidValueType(path: "voice.audioCuesEnabled")
            ),
        ]

        for (sourceData, expectedError) in fixtures {
            try sourceData.write(to: fileURL, options: .atomic)
            do {
                _ = try await repository.load()
                Issue.record("Expected settings load to fail")
            } catch let error as IOSAppSettingsRepositoryError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            #expect(try Data(contentsOf: fileURL) == sourceData)
        }
    }

    @Test func sourceAndEncodingLimitsHaveDistinctPublicFailures() async throws {
        let containerURL = makeTemporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let applicationSupportURL = containerURL.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        let fileURL = IOSAppSettingsStorageLocation.fileURL(in: applicationSupportURL)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let repository = IOSAppSettingsRepository(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let oversizedSource = Data(repeating: 0x61, count: 1_024 * 1_024 + 1)
        try oversizedSource.write(to: fileURL)

        do {
            _ = try await repository.load()
            Issue.record("Expected sourceTooLarge")
        } catch let error as IOSAppSettingsRepositoryError {
            #expect(error == .sourceTooLarge)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(try Data(contentsOf: fileURL) == oversizedSource)

        var settings = IOSAppSettings.defaults
        settings.transcriptionConfiguration.freeformPrompt = String(
            repeating: "x",
            count: 1_024 * 1_024
        )
        do {
            try await repository.save(settings)
            Issue.record("Expected encodedDataTooLarge")
        } catch let error as IOSAppSettingsRepositoryError {
            #expect(error == .encodedDataTooLarge)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(try Data(contentsOf: fileURL) == oversizedSource)
    }

    private func fixtureSettings() -> IOSAppSettings {
        IOSAppSettings(
            transcriptionConfiguration: TranscriptionConfiguration(
                model: "ios-model",
                language: .german,
                customLanguageCode: "",
                freeformPrompt: "iOS prompt"
            ),
            textCorrectionConfiguration: TextCorrectionConfiguration(
                isEnabled: true,
                modelPreset: .balanced,
                customModel: "",
                prompt: "correct"
            ),
            localTextCleanupEnabled: false,
            translationConfiguration: TranslationConfiguration(
                actionPreferenceEnabled: true,
                sourceMode: .override,
                sourceLanguage: .german,
                targetLanguage: .english,
                model: "translate-model",
                prompt: "translate"
            ),
            voiceSessionPreferences: VoiceSessionPreferences(
                audioCuesEnabled: false,
                recordingStopTailDuration: .seconds1
            ),
            recordingCachePolicy: .unlimited
        )
    }

    private func makeTemporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-ios-settings-tests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
