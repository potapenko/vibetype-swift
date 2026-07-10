import Foundation
import HoldTypeDomain
import HoldTypePersistence
import Testing

struct IOSLibraryPersistenceIOSTests {
    private static let commandID = UUID(
        uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    )!
    private static let ruleID = UUID(
        uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
    )!

    @Test func publicRuntimeContractWorksThroughNormalIOSImports() {
        let content = IOSLibraryContent.defaults

        #expect(content.customDictionary == .empty)
        #expect(content.emojiCommandsConfiguration == .defaults)
        #expect(content.replacementRules.isEmpty)
        requireSendable(IOSLibraryContent.self)
        #expect(((content as Any) is any Encodable) == false)
        #expect(((content as Any) is any Decodable) == false)
    }

    @Test func publicRepositoryUsesStableProtectedBackupEligibleLocation() async throws {
        let containerURL = makeTemporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let applicationSupportURL = containerURL.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        let fileURL = applicationSupportURL
            .appendingPathComponent("HoldType", isDirectory: true)
            .appendingPathComponent("ios-library.json", isDirectory: false)
        #expect(IOSLibraryStorageLocation.fileURL(in: applicationSupportURL) == fileURL)

        let repository = IOSLibraryRepository(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        #expect(try await repository.load() == .defaults)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        try await repository.save(fixtureContent())
        let loaded = try await repository.load()
        #expect(loaded.customDictionary.entries == ["HoldType", "Alpha,Beta"])
        #expect(loaded.emojiCommandsConfiguration.enabledBuiltInSetIDs == ["fr"])
        #expect(loaded.emojiCommandsConfiguration.customCommands.count == 1)
        #expect(loaded.emojiCommandsConfiguration.customCommands[0].command == "launch now")
        #expect(loaded.replacementRules.map(\.search) == ["", ""])
        #expect(
            try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == false
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #if targetEnvironment(simulator)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            #expect(protection == .complete)
        }
        #else
        #expect(attributes[.protectionKey] as? FileProtectionType == .complete)
        #endif
    }

    @Test func corruptUnsupportedAndStrictValidationFailuresPreserveSourceBytes() async throws {
        let containerURL = makeTemporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let applicationSupportURL = containerURL.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        let fileURL = IOSLibraryStorageLocation.fileURL(in: applicationSupportURL)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let repository = IOSLibraryRepository(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let fixtures: [(Data, IOSLibraryRepositoryError)] = [
            (Data("not-json".utf8), .malformedData),
            (
                Data(#"{"schemaVersion":2}"#.utf8),
                .unsupportedSchemaVersion
            ),
            (
                Data(
                    #"{"emojiCommands":{"enabledBuiltInSetIDs":["EN"]},"schemaVersion":1}"#.utf8
                ),
                .unknownBuiltInSetIdentifier(
                    path: "emojiCommands.enabledBuiltInSetIDs"
                )
            ),
            (
                Data(
                    #"{"emojiCommands":{"enabledBuiltInSetIDs":["en","ru"]},"schemaVersion":1}"#.utf8
                ),
                .invalidBuiltInSetSelection(
                    path: "emojiCommands.enabledBuiltInSetIDs"
                )
            ),
        ]

        for (sourceData, expectedError) in fixtures {
            try sourceData.write(to: fileURL, options: .atomic)
            do {
                _ = try await repository.load()
                Issue.record("Expected Library load to fail")
            } catch let error as IOSLibraryRepositoryError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            #expect(try Data(contentsOf: fileURL) == sourceData)
        }
    }

    @Test func sourceAndCanonicalEncodingLimitsStayDistinctOnIOS() async throws {
        let containerURL = makeTemporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: containerURL) }
        let applicationSupportURL = containerURL.appendingPathComponent(
            "Library/Application Support",
            isDirectory: true
        )
        let fileURL = IOSLibraryStorageLocation.fileURL(in: applicationSupportURL)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let repository = IOSLibraryRepository(
            applicationSupportDirectoryURL: applicationSupportURL
        )
        let oversizedSource = Data(repeating: 0x61, count: 1_024 * 1_024 + 1)
        try oversizedSource.write(to: fileURL)

        do {
            _ = try await repository.load()
            Issue.record("Expected sourceTooLarge")
        } catch let error as IOSLibraryRepositoryError {
            #expect(error == .sourceTooLarge)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let oversizedContent = IOSLibraryContent(
            customDictionary: CustomDictionary(entries: [
                String(repeating: "x", count: 1_024 * 1_024),
            ])
        )
        do {
            try await repository.save(oversizedContent)
            Issue.record("Expected encodedDataTooLarge")
        } catch let error as IOSLibraryRepositoryError {
            #expect(error == .encodedDataTooLarge)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(try Data(contentsOf: fileURL) == oversizedSource)
    }

    private func fixtureContent() -> IOSLibraryContent {
        IOSLibraryContent(
            customDictionary: CustomDictionary(entries: [
                " HoldType ", "holdtype", "Alpha,Beta",
            ]),
            emojiCommandsConfiguration: EmojiCommandsConfiguration(
                enabledBuiltInSetIDs: ["fr"],
                customCommands: [
                    CustomEmojiCommand(
                        id: Self.commandID,
                        emoji: " 🚀 ",
                        command: " ",
                        aliases: [" launch   now "],
                        isEnabled: true
                    ),
                ]
            ),
            replacementRules: [
                TextReplacementRule(
                    id: Self.ruleID,
                    search: "",
                    replacement: "one"
                ),
                TextReplacementRule(
                    search: "",
                    replacement: "two",
                    isEnabled: false
                ),
            ]
        )
    }

    private func makeTemporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-ios-library-tests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}
}
