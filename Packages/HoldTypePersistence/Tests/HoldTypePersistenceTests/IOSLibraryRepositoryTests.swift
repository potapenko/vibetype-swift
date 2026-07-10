import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSLibraryRepositoryTests {
    private static let firstCommandID = UUID(
        uuidString: "11111111-1111-1111-1111-111111111111"
    )!
    private static let aliasesOnlyCommandID = UUID(
        uuidString: "22222222-2222-2222-2222-222222222222"
    )!
    private static let semanticDuplicateCommandID = UUID(
        uuidString: "33333333-3333-3333-3333-333333333333"
    )!
    private static let firstRuleID = UUID(
        uuidString: "44444444-4444-4444-4444-444444444444"
    )!
    private static let secondRuleID = UUID(
        uuidString: "55555555-5555-5555-5555-555555555555"
    )!

    @Test func runtimeValueHasDocumentedDefaultsAndIsNotAWireDTO() {
        let content = IOSLibraryContent.defaults

        #expect(content == IOSLibraryContent())
        #expect(content.customDictionary == .empty)
        #expect(content.emojiCommandsConfiguration == .defaults)
        #expect(content.replacementRules.isEmpty)
        requireSendable(IOSLibraryContent.self)
        #expect(((content as Any) is any Encodable) == false)
        #expect(((content as Any) is any Decodable) == false)
    }

    @Test func storageLocationUsesStableAppPrivateRelativePath() {
        let applicationSupportURL = URL(
            fileURLWithPath: "/private/app-container/Library/Application Support",
            isDirectory: true
        )

        #expect(
            IOSLibraryStorageLocation.fileURL(in: applicationSupportURL).path ==
                "/private/app-container/Library/Application Support/HoldType/ios-library.json"
        )
        #expect(IOSLibraryStorageLocation.directoryName == "HoldType")
        #expect(IOSLibraryStorageLocation.fileName == "ios-library.json")
    }

    @Test func canonicalV1SaveNormalizesLibraryAndPreservesReplacementOrder() async throws {
        let fileSystem = IOSLibraryFileSystemFake()
        let repository = makeRepository(fileSystem: fileSystem)

        try await repository.save(fixtureContent())

        let expectedJSON = [
            #"{"dictionary":{"entries":["HoldType","Alpha,Beta","Line\nBreak"]},"#,
            #""emojiCommands":{"customCommands":["#,
            #"{"aliases":["Launch Emoji"],"command":"Emoji Rocket","emoji":"🚀","#,
            #""id":"11111111-1111-1111-1111-111111111111","isEnabled":false},"#,
            #"{"aliases":[],"command":"ship it","emoji":"✅","#,
            #""id":"22222222-2222-2222-2222-222222222222","isEnabled":true}],"#,
            #""enabledBuiltInSetIDs":["pt"],"isEnabled":true},"#,
            #""replacementRules":["#,
            #"{"id":"44444444-4444-4444-4444-444444444444","isEnabled":true,"#,
            #""replacement":" keep ","search":""},"#,
            #"{"id":"55555555-5555-5555-5555-555555555555","isEnabled":false,"#,
            #""replacement":" \nvalue \n","search":"  A\nB  "}],"schemaVersion":1}"#,
        ].joined()
        #expect(fileSystem.data == Data(expectedJSON.utf8))

        let loaded = try await repository.load()
        #expect(
            loaded.customDictionary.entries == [
                "HoldType", "Alpha,Beta", "Line\nBreak",
            ]
        )
        #expect(
            loaded.emojiCommandsConfiguration.customCommands.map(\.id) == [
                Self.firstCommandID, Self.aliasesOnlyCommandID,
            ]
        )
        #expect(!loaded.emojiCommandsConfiguration.customCommands[0].isEnabled)
        #expect(loaded.emojiCommandsConfiguration.customCommands[0].aliases == ["Launch Emoji"])
        #expect(loaded.emojiCommandsConfiguration.customCommands[1].command == "ship it")
        #expect(loaded.emojiCommandsConfiguration.customCommands[1].aliases.isEmpty)
        #expect(loaded.replacementRules.map(\.id) == [Self.firstRuleID, Self.secondRuleID])
        #expect(loaded.replacementRules.map(\.search) == ["", "  A\nB  "])
        #expect(loaded.replacementRules.map(\.replacement) == [" keep ", " \nvalue \n"])
    }

    @Test func missingFileReturnsDefaultsWithoutWriting() async throws {
        let fileSystem = IOSLibraryFileSystemFake(data: nil)
        let repository = makeRepository(fileSystem: fileSystem)

        #expect(try await repository.load() == .defaults)
        #expect(fileSystem.replacementCallCount == 0)
        #expect(fileSystem.data == nil)
        #expect(fileSystem.readPolicies == [expectedFilePolicy])
    }

    @Test func missingKnownGroupsAndGroupFieldsDefaultWithoutRewriting() async throws {
        let defaultsData = Data(#"{"schemaVersion":1}"#.utf8)
        let defaultsFileSystem = IOSLibraryFileSystemFake(data: defaultsData)
        let defaultsRepository = makeRepository(fileSystem: defaultsFileSystem)
        #expect(try await defaultsRepository.load() == .defaults)
        #expect(defaultsFileSystem.data == defaultsData)
        #expect(defaultsFileSystem.replacementCallCount == 0)

        let partialData = Data(
            #"{"dictionary":{"entries":[" One ","one"]},"emojiCommands":{"isEnabled":false},"schemaVersion":1}"#.utf8
        )
        let partialFileSystem = IOSLibraryFileSystemFake(data: partialData)
        let partialRepository = makeRepository(fileSystem: partialFileSystem)
        let loaded = try await partialRepository.load()

        #expect(loaded.customDictionary.entries == ["One"])
        #expect(!loaded.emojiCommandsConfiguration.isEnabled)
        #expect(loaded.emojiCommandsConfiguration.enabledBuiltInSetIDs == ["en"])
        #expect(loaded.emojiCommandsConfiguration.customCommands.isEmpty)
        #expect(loaded.replacementRules.isEmpty)
        #expect(partialFileSystem.data == partialData)
        #expect(partialFileSystem.replacementCallCount == 0)
    }

    @Test func malformedRootsAndSchemaFailuresAreTypedAndPreserveBytes() async {
        let fixtures: [(Data, IOSLibraryRepositoryError)] = [
            (Data("not-json".utf8), .malformedData),
            (Data("[]".utf8), .topLevelNotObject),
            (Data("null".utf8), .topLevelNotObject),
            (Data(#"{}"#.utf8), .missingSchemaVersion),
            (
                Data(#"{"schemaVersion":1.0}"#.utf8),
                .invalidValueType(path: "schemaVersion")
            ),
            (
                Data(#"{"schemaVersion":true}"#.utf8),
                .invalidValueType(path: "schemaVersion")
            ),
            (
                Data(#"{"schemaVersion":0}"#.utf8),
                .unsupportedSchemaVersion
            ),
            (
                Data(#"{"schemaVersion":2}"#.utf8),
                .unsupportedSchemaVersion
            ),
        ]

        for (data, expectedError) in fixtures {
            await expectLoadFailure(data: data, expectedError: expectedError)
        }
    }

    @Test func nullWrongTypeAndNonObjectRowsAreRejectedWithoutWriting() async {
        let fixtures: [(String, IOSLibraryRepositoryError)] = [
            (
                #"{"dictionary":null,"schemaVersion":1}"#,
                .invalidValueType(path: "dictionary")
            ),
            (
                #"{"dictionary":{"entries":null},"schemaVersion":1}"#,
                .invalidValueType(path: "dictionary.entries")
            ),
            (
                #"{"emojiCommands":{"isEnabled":"true"},"schemaVersion":1}"#,
                .invalidValueType(path: "emojiCommands.isEnabled")
            ),
            (
                #"{"emojiCommands":{"enabledBuiltInSetIDs":[1]},"schemaVersion":1}"#,
                .invalidValueType(path: "emojiCommands.enabledBuiltInSetIDs")
            ),
            (
                #"{"emojiCommands":{"customCommands":[null]},"schemaVersion":1}"#,
                .invalidValueType(path: "emojiCommands.customCommands")
            ),
            (
                #"{"replacementRules":["row"],"schemaVersion":1}"#,
                .invalidValueType(path: "replacementRules")
            ),
        ]

        for (json, expectedError) in fixtures {
            await expectLoadFailure(
                data: Data(json.utf8),
                expectedError: expectedError
            )
        }
    }

    @Test func everyExistingRowFieldIsRequired() async throws {
        let customCommand: [String: Any] = [
            "id": Self.firstCommandID.uuidString,
            "emoji": "🚀",
            "command": "emoji rocket",
            "aliases": ["launch"],
            "isEnabled": true,
        ]
        for key in customCommand.keys {
            var missingFieldCommand = customCommand
            missingFieldCommand.removeValue(forKey: key)
            let data = try rootData(
                emojiCommands: ["customCommands": [missingFieldCommand]]
            )
            await expectLoadFailure(
                data: data,
                expectedError: .missingRequiredValue(
                    path: "emojiCommands.customCommands[].\(key)"
                )
            )
        }

        let replacementRule: [String: Any] = [
            "id": Self.firstRuleID.uuidString,
            "search": "",
            "replacement": "",
            "isEnabled": true,
        ]
        for key in replacementRule.keys {
            var missingFieldRule = replacementRule
            missingFieldRule.removeValue(forKey: key)
            let data = try rootData(replacementRules: [missingFieldRule])
            await expectLoadFailure(
                data: data,
                expectedError: .missingRequiredValue(
                    path: "replacementRules[].\(key)"
                )
            )
        }
    }

    @Test func unexpectedFieldsAtEveryLevelAreRedactedAndPreserveBytes() async throws {
        let fixtures: [(Data, IOSLibraryRepositoryError)] = [
            (
                Data(#"{"future":"secret","schemaVersion":1}"#.utf8),
                .unexpectedFields(path: "$")
            ),
            (
                Data(#"{"dictionary":{"future":"secret"},"schemaVersion":1}"#.utf8),
                .unexpectedFields(path: "dictionary")
            ),
            (
                Data(#"{"emojiCommands":{"future":"secret"},"schemaVersion":1}"#.utf8),
                .unexpectedFields(path: "emojiCommands")
            ),
            (
                try rootData(emojiCommands: [
                    "customCommands": [[
                        "id": Self.firstCommandID.uuidString,
                        "emoji": "🚀",
                        "command": "launch",
                        "aliases": [],
                        "isEnabled": true,
                        "future": "secret",
                    ]],
                ]),
                .unexpectedFields(path: "emojiCommands.customCommands[]")
            ),
            (
                try rootData(replacementRules: [[
                    "id": Self.firstRuleID.uuidString,
                    "search": "secret",
                    "replacement": "secret",
                    "isEnabled": true,
                    "future": "secret",
                ]]),
                .unexpectedFields(path: "replacementRules[]")
            ),
        ]

        for (data, expectedError) in fixtures {
            await expectLoadFailure(data: data, expectedError: expectedError)
        }
    }

    @Test func builtInSetIdentifiersAreExactAndEveryItemPrecedesCardinality() async throws {
        for identifier in ["EN", " en ", "future-secret"] {
            let data = try rootData(emojiCommands: [
                "enabledBuiltInSetIDs": [identifier],
            ])
            await expectLoadFailure(
                data: data,
                expectedError: .unknownBuiltInSetIdentifier(
                    path: "emojiCommands.enabledBuiltInSetIDs"
                )
            )

            var content = IOSLibraryContent.defaults
            content.emojiCommandsConfiguration.enabledBuiltInSetIDs = [identifier]
            await expectSaveFailure(
                content,
                expectedError: .unknownBuiltInSetIdentifier(
                    path: "emojiCommands.enabledBuiltInSetIDs"
                )
            )
        }

        let mixedUnknownData = try rootData(emojiCommands: [
            "enabledBuiltInSetIDs": ["en", "future-secret"],
        ])
        await expectLoadFailure(
            data: mixedUnknownData,
            expectedError: .unknownBuiltInSetIdentifier(
                path: "emojiCommands.enabledBuiltInSetIDs"
            )
        )
        var mixedUnknownContent = IOSLibraryContent.defaults
        mixedUnknownContent.emojiCommandsConfiguration.enabledBuiltInSetIDs = [
            "en", "future-secret",
        ]
        await expectSaveFailure(
            mixedUnknownContent,
            expectedError: .unknownBuiltInSetIdentifier(
                path: "emojiCommands.enabledBuiltInSetIDs"
            )
        )

        let twoKnownData = try rootData(emojiCommands: [
            "enabledBuiltInSetIDs": ["en", "ru"],
        ])
        await expectLoadFailure(
            data: twoKnownData,
            expectedError: .invalidBuiltInSetSelection(
                path: "emojiCommands.enabledBuiltInSetIDs"
            )
        )

        var twoKnownContent = IOSLibraryContent.defaults
        twoKnownContent.emojiCommandsConfiguration.enabledBuiltInSetIDs = ["en", "ru"]
        await expectSaveFailure(
            twoKnownContent,
            expectedError: .invalidBuiltInSetSelection(
                path: "emojiCommands.enabledBuiltInSetIDs"
            )
        )

        for identifiers in [[], ["en"], ["ru"], ["es"], ["de"], ["fr"], ["pt"]] {
            let data = try rootData(emojiCommands: [
                "enabledBuiltInSetIDs": identifiers,
            ])
            let fileSystem = IOSLibraryFileSystemFake(data: data)
            let loaded = try await makeRepository(fileSystem: fileSystem).load()
            #expect(loaded.emojiCommandsConfiguration.enabledBuiltInSetIDs == identifiers)
        }
    }

    @Test func duplicateRawCommandIdentifierWinsBeforeUnusableRowValidation() async throws {
        let duplicateRows: [[String: Any]] = [
            [
                "id": Self.firstCommandID.uuidString,
                "emoji": " ",
                "command": " ",
                "aliases": [],
                "isEnabled": true,
            ],
            [
                "id": Self.firstCommandID.uuidString,
                "emoji": "🚀",
                "command": "launch",
                "aliases": [],
                "isEnabled": true,
            ],
        ]
        let data = try rootData(emojiCommands: ["customCommands": duplicateRows])
        let expectedError = IOSLibraryRepositoryError.duplicateIdentifier(
            path: "emojiCommands.customCommands[].id"
        )
        await expectLoadFailure(data: data, expectedError: expectedError)

        var content = IOSLibraryContent.defaults
        content.emojiCommandsConfiguration.customCommands = [
            CustomEmojiCommand(
                id: Self.firstCommandID,
                emoji: " ",
                command: " "
            ),
            CustomEmojiCommand(
                id: Self.firstCommandID,
                emoji: "🚀",
                command: "launch"
            ),
        ]
        await expectSaveFailure(content, expectedError: expectedError)
    }

    @Test func emptyBuiltInSelectionAndDisabledCustomStateRoundTripThroughSave() async throws {
        let command = CustomEmojiCommand(
            id: Self.firstCommandID,
            emoji: "🚀",
            command: "launch",
            isEnabled: false
        )
        let content = IOSLibraryContent(
            emojiCommandsConfiguration: EmojiCommandsConfiguration(
                isEnabled: false,
                enabledBuiltInSetIDs: [],
                customCommands: [command]
            )
        )
        let fileSystem = IOSLibraryFileSystemFake()
        let repository = makeRepository(fileSystem: fileSystem)

        try await repository.save(content)
        let loaded = try await repository.load()

        #expect(!loaded.emojiCommandsConfiguration.isEnabled)
        #expect(loaded.emojiCommandsConfiguration.enabledBuiltInSetIDs.isEmpty)
        #expect(loaded.emojiCommandsConfiguration.customCommands == [command])
    }

    @Test func unusableCommandRowsFailInsteadOfBeingDiscarded() async throws {
        let fixtures: [([String: Any], IOSLibraryRepositoryError)] = [
            (
                [
                    "id": Self.firstCommandID.uuidString,
                    "emoji": " \n ",
                    "command": "launch",
                    "aliases": [],
                    "isEnabled": true,
                ],
                .invalidValue(path: "emojiCommands.customCommands[].emoji")
            ),
            (
                [
                    "id": Self.firstCommandID.uuidString,
                    "emoji": "🚀",
                    "command": " \n ",
                    "aliases": [" \t "],
                    "isEnabled": true,
                ],
                .invalidValue(path: "emojiCommands.customCommands[].command")
            ),
        ]

        for (row, expectedError) in fixtures {
            let data = try rootData(emojiCommands: ["customCommands": [row]])
            await expectLoadFailure(data: data, expectedError: expectedError)

            var content = IOSLibraryContent.defaults
            content.emojiCommandsConfiguration.customCommands = [
                CustomEmojiCommand(
                    id: Self.firstCommandID,
                    emoji: row["emoji"] as? String ?? "",
                    command: row["command"] as? String ?? "",
                    aliases: row["aliases"] as? [String] ?? [],
                    isEnabled: true
                ),
            ]
            await expectSaveFailure(content, expectedError: expectedError)
        }
    }

    @Test func duplicateReplacementIdentifiersFailButRepeatedRawSearchIsAllowed() async throws {
        let duplicateRows: [[String: Any]] = [
            replacementRuleObject(id: Self.firstRuleID, search: "same", replacement: "one"),
            replacementRuleObject(id: Self.firstRuleID, search: "same", replacement: "two"),
        ]
        let duplicateData = try rootData(replacementRules: duplicateRows)
        await expectLoadFailure(
            data: duplicateData,
            expectedError: .duplicateIdentifier(path: "replacementRules[].id")
        )
        let duplicateContent = IOSLibraryContent(replacementRules: [
            TextReplacementRule(
                id: Self.firstRuleID,
                search: "same",
                replacement: "one"
            ),
            TextReplacementRule(
                id: Self.firstRuleID,
                search: "same",
                replacement: "two"
            ),
        ])
        await expectSaveFailure(
            duplicateContent,
            expectedError: .duplicateIdentifier(path: "replacementRules[].id")
        )

        let validRows: [[String: Any]] = [
            replacementRuleObject(id: Self.firstRuleID, search: "", replacement: "one"),
            replacementRuleObject(id: Self.secondRuleID, search: "", replacement: "two"),
        ]
        let validData = try rootData(replacementRules: validRows)
        let fileSystem = IOSLibraryFileSystemFake(data: validData)
        let loaded = try await makeRepository(fileSystem: fileSystem).load()
        #expect(loaded.replacementRules.map(\.search) == ["", ""])
        #expect(loaded.replacementRules.map(\.replacement) == ["one", "two"])
    }

    @Test func sameIdentifierMayBeReusedAcrossIndependentCollections() async throws {
        let content = IOSLibraryContent(
            emojiCommandsConfiguration: EmojiCommandsConfiguration(
                customCommands: [
                    CustomEmojiCommand(
                        id: Self.firstCommandID,
                        emoji: "🚀",
                        command: "launch"
                    ),
                ]
            ),
            replacementRules: [
                TextReplacementRule(
                    id: Self.firstCommandID,
                    search: "launch",
                    replacement: "go"
                ),
            ]
        )
        let fileSystem = IOSLibraryFileSystemFake()
        let repository = makeRepository(fileSystem: fileSystem)

        try await repository.save(content)
        #expect(try await repository.load() == content)
    }

    @Test func malformedIdentifiersDoNotLeakRawValues() async throws {
        let sensitiveIdentifier = "sk-secret-invalid-identifier"
        let data = try rootData(replacementRules: [[
            "id": sensitiveIdentifier,
            "search": "/private/app/secret",
            "replacement": "EACCES",
            "isEnabled": true,
        ]])
        let fileSystem = IOSLibraryFileSystemFake(data: data)
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            _ = try await repository.load()
            Issue.record("Expected invalid identifier")
        } catch let error as IOSLibraryRepositoryError {
            #expect(error == .invalidIdentifier(path: "replacementRules[].id"))
            assertPublicRenderings(
                of: error,
                exclude: [sensitiveIdentifier, "/private/app/secret", "EACCES"]
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(fileSystem.data == data)
        #expect(fileSystem.replacementCallCount == 0)
    }

    @Test func presentEntityFieldsAndArrayElementsMustHaveExactTypes() async throws {
        await expectLoadFailure(
            data: try rootData(dictionary: ["entries": ["valid", 42]]),
            expectedError: .invalidValueType(path: "dictionary.entries")
        )

        let customCommand: [String: Any] = [
            "id": Self.firstCommandID.uuidString,
            "emoji": "🚀",
            "command": "launch",
            "aliases": ["go"],
            "isEnabled": true,
        ]
        let invalidCustomValues: [(String, Any)] = [
            ("id", 42),
            ("emoji", 42),
            ("command", false),
            ("aliases", ["go", 42]),
            ("isEnabled", "true"),
        ]
        for (key, value) in invalidCustomValues {
            var invalidRow = customCommand
            invalidRow[key] = value
            await expectLoadFailure(
                data: try rootData(emojiCommands: ["customCommands": [invalidRow]]),
                expectedError: .invalidValueType(
                    path: "emojiCommands.customCommands[].\(key)"
                )
            )
        }

        let replacementRule: [String: Any] = [
            "id": Self.firstRuleID.uuidString,
            "search": "find",
            "replacement": "replace",
            "isEnabled": true,
        ]
        let invalidRuleValues: [(String, Any)] = [
            ("id", 42),
            ("search", false),
            ("replacement", 42),
            ("isEnabled", "true"),
        ]
        for (key, value) in invalidRuleValues {
            var invalidRow = replacementRule
            invalidRow[key] = value
            await expectLoadFailure(
                data: try rootData(replacementRules: [invalidRow]),
                expectedError: .invalidValueType(path: "replacementRules[].\(key)")
            )
        }
    }

    @Test func attackerFieldsValuesPathsAndSystemErrorsStayOutOfPublicErrors() async {
        let sensitiveField = "sk-secret-future-field"
        let sensitiveValue = "/private/app/HoldType/secret EACCES 13"
        let data = Data(
            "{\"schemaVersion\":1,\"\(sensitiveField)\":\"\(sensitiveValue)\"}".utf8
        )
        let fileSystem = IOSLibraryFileSystemFake(data: data)
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            _ = try await repository.load()
            Issue.record("Expected unexpected fields")
        } catch let error as IOSLibraryRepositoryError {
            #expect(error == .unexpectedFields(path: "$"))
            assertPublicRenderings(
                of: error,
                exclude: [sensitiveField, sensitiveValue, "/private/app", "EACCES", "13"]
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let readFailureSystem = IOSLibraryFileSystemFake(
            readError: IOSLibrarySensitiveFileError()
        )
        do {
            _ = try await makeRepository(fileSystem: readFailureSystem).load()
            Issue.record("Expected read failure")
        } catch let error as IOSLibraryRepositoryError {
            #expect(error == .readFailed)
            assertPublicRenderings(
                of: error,
                exclude: ["/private/app", "EACCES", "13"]
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        let writeFailureSystem = IOSLibraryFileSystemFake(
            data: Data("durable".utf8),
            replacementError: IOSLibrarySensitiveFileError()
        )
        do {
            try await makeRepository(fileSystem: writeFailureSystem).save(.defaults)
            Issue.record("Expected write failure")
        } catch let error as IOSLibraryRepositoryError {
            #expect(error == .writeFailed)
            assertPublicRenderings(
                of: error,
                exclude: ["/private/app", "EACCES", "13"]
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(writeFailureSystem.data == Data("durable".utf8))
    }

    @Test func sourceAndCanonicalEncodingLimitsAreDistinctAndPreserveBytes() async {
        let sourceData = Data("oversized-library-source".utf8)
        let sourceFileSystem = IOSLibraryFileSystemFake(
            data: sourceData,
            readError: ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded
        )
        let sourceRepository = makeRepository(fileSystem: sourceFileSystem)

        do {
            _ = try await sourceRepository.load()
            Issue.record("Expected source limit failure")
        } catch let error as IOSLibraryRepositoryError {
            #expect(error == .sourceTooLarge)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(sourceFileSystem.data == sourceData)
        #expect(sourceFileSystem.replacementCallCount == 0)

        let previousData = Data("durable-library".utf8)
        let oversizedContent = IOSLibraryContent(
            customDictionary: CustomDictionary(entries: [
                "sk-sensitive-entry-" + String(repeating: "x", count: 1_024 * 1_024),
            ])
        )
        let encodingFileSystem = IOSLibraryFileSystemFake(data: previousData)
        let encodingRepository = makeRepository(fileSystem: encodingFileSystem)
        do {
            try await encodingRepository.save(oversizedContent)
            Issue.record("Expected canonical encoding limit failure")
        } catch let error as IOSLibraryRepositoryError {
            #expect(error == .encodedDataTooLarge)
            assertPublicRenderings(of: error, exclude: ["sk-sensitive-entry"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(encodingFileSystem.data == previousData)
        #expect(encodingFileSystem.replacementCallCount == 0)
    }

    @Test func failedAtomicReplacementPreservesPreviousBytes() async {
        let previousData = Data("previous-library-bytes".utf8)
        let fileSystem = IOSLibraryFileSystemFake(
            data: previousData,
            replacementError: IOSLibraryFileSystemFakeError.replacementFailed
        )
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            try await repository.save(.defaults)
            Issue.record("Expected write failure")
        } catch let error as IOSLibraryRepositoryError {
            #expect(error == .writeFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(fileSystem.data == previousData)
        #expect(fileSystem.replacementCallCount == 1)
    }

    @Test func everyReadAndReplacementUsesOneMiBCompleteBackupEligiblePolicy() async throws {
        let fileSystem = IOSLibraryFileSystemFake()
        let repository = makeRepository(fileSystem: fileSystem)

        _ = try await repository.load()
        try await repository.save(.defaults)
        try await repository.save(fixtureContent())

        #expect(fileSystem.readPolicies == [expectedFilePolicy])
        #expect(fileSystem.replacementPolicies == [expectedFilePolicy, expectedFilePolicy])
    }

    @Test func foundationReplacementMakesFinalDestinationProtectedAndBackupEligible() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-ios-library-backup-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = directoryURL.appendingPathComponent("ios-library.json")
        #expect(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        var excludedURL = fileURL
        var excludedValues = URLResourceValues()
        excludedValues.isExcludedFromBackup = true
        try excludedURL.setResourceValues(excludedValues)
        try Data("old-library".utf8).write(to: fileURL)
        try await Task.sleep(for: .milliseconds(20))

        let repository = IOSLibraryRepository(fileURL: fileURL)
        try await repository.save(.defaults)

        #expect(try await repository.load() == .defaults)
        var refreshedFileURL = URL(fileURLWithPath: fileURL.path)
        refreshedFileURL.removeAllCachedResourceValues()
        #expect(
            try refreshedFileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
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

    @Test func actorSerializesConcurrentLoadsAndSaves() async {
        let fileSystem = IOSLibraryFileSystemFake(operationDelay: 0.002)
        let repository = makeRepository(fileSystem: fileSystem)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<24 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        try? await repository.save(.defaults)
                    } else {
                        _ = try? await repository.load()
                    }
                }
            }
        }

        #expect(fileSystem.operationCallCount == 24)
        #expect(fileSystem.maximumConcurrentOperationCount == 1)
    }

    private var expectedFilePolicy: ProtectedAtomicMetadataFilePolicy {
        ProtectedAtomicMetadataFilePolicy(
            maximumByteCount: 1_024 * 1_024,
            fileProtection: .complete,
            excludesFromBackup: false
        )
    }

    private func fixtureContent() -> IOSLibraryContent {
        IOSLibraryContent(
            customDictionary: CustomDictionary(entries: [
                " HoldType ", "holdtype", "Alpha,Beta", "Line\nBreak",
            ]),
            emojiCommandsConfiguration: EmojiCommandsConfiguration(
                enabledBuiltInSetIDs: ["pt"],
                customCommands: [
                    CustomEmojiCommand(
                        id: Self.firstCommandID,
                        emoji: " 🚀 ",
                        command: " Emoji   Rocket ",
                        aliases: [" Launch Emoji ", "launch emoji", ""],
                        isEnabled: false
                    ),
                    CustomEmojiCommand(
                        id: Self.aliasesOnlyCommandID,
                        emoji: " ✅ ",
                        command: " \n ",
                        aliases: [" ship   it ", "Ship It"],
                        isEnabled: true
                    ),
                    CustomEmojiCommand(
                        id: Self.semanticDuplicateCommandID,
                        emoji: "🚀",
                        command: "émóji rocket",
                        isEnabled: true
                    ),
                ]
            ),
            replacementRules: [
                TextReplacementRule(
                    id: Self.firstRuleID,
                    search: "",
                    replacement: " keep "
                ),
                TextReplacementRule(
                    id: Self.secondRuleID,
                    search: "  A\nB  ",
                    replacement: " \nvalue \n",
                    isEnabled: false
                ),
            ]
        )
    }

    private func makeRepository(
        fileSystem: IOSLibraryFileSystemFake
    ) -> IOSLibraryRepository {
        IOSLibraryRepository(
            fileURL: URL(fileURLWithPath: "/app-private/HoldType/ios-library.json"),
            fileSystem: fileSystem
        )
    }

    private func expectLoadFailure(
        data: Data,
        expectedError: IOSLibraryRepositoryError
    ) async {
        let fileSystem = IOSLibraryFileSystemFake(data: data)
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            _ = try await repository.load()
            Issue.record("Expected load failure \(expectedError)")
        } catch let error as IOSLibraryRepositoryError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(fileSystem.data == data)
        #expect(fileSystem.replacementCallCount == 0)
    }

    private func expectSaveFailure(
        _ content: IOSLibraryContent,
        expectedError: IOSLibraryRepositoryError
    ) async {
        let durableData = Data("durable-library".utf8)
        let fileSystem = IOSLibraryFileSystemFake(data: durableData)
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            try await repository.save(content)
            Issue.record("Expected save failure \(expectedError)")
        } catch let error as IOSLibraryRepositoryError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(fileSystem.data == durableData)
        #expect(fileSystem.replacementCallCount == 0)
    }

    private func rootData(
        dictionary: [String: Any]? = nil,
        emojiCommands: [String: Any]? = nil,
        replacementRules: [[String: Any]]? = nil
    ) throws -> Data {
        var root: [String: Any] = ["schemaVersion": 1]
        if let dictionary {
            root["dictionary"] = dictionary
        }
        if let emojiCommands {
            root["emojiCommands"] = emojiCommands
        }
        if let replacementRules {
            root["replacementRules"] = replacementRules
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func replacementRuleObject(
        id: UUID,
        search: String,
        replacement: String
    ) -> [String: Any] {
        [
            "id": id.uuidString,
            "search": search,
            "replacement": replacement,
            "isEnabled": true,
        ]
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}

    private func assertPublicRenderings(
        of error: IOSLibraryRepositoryError,
        exclude sensitiveValues: [String]
    ) {
        var dumpedError = ""
        dump(error, to: &dumpedError)
        let renderings = [
            String(describing: error),
            String(reflecting: error),
            error.localizedDescription,
            dumpedError,
        ]
        for rendering in renderings {
            for sensitiveValue in sensitiveValues {
                #expect(!rendering.contains(sensitiveValue))
            }
        }
    }
}

private enum IOSLibraryFileSystemFakeError: Error {
    case replacementFailed
}

private struct IOSLibrarySensitiveFileError: Error, CustomStringConvertible {
    let description = "/private/app/HoldType/ios-library.json EACCES 13"
}

private final class IOSLibraryFileSystemFake:
    ProtectedAtomicMetadataFileSystem,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedData: Data?
    private var storedReadPolicies: [ProtectedAtomicMetadataFilePolicy] = []
    private var storedReplacementCallCount = 0
    private var storedReplacementPolicies: [ProtectedAtomicMetadataFilePolicy] = []
    private var storedOperationCallCount = 0
    private var activeOperationCount = 0
    private var storedMaximumConcurrentOperationCount = 0
    private let readError: Error?
    private let replacementError: Error?
    private let operationDelay: TimeInterval

    var data: Data? {
        lock.withLock { storedData }
    }

    var readPolicies: [ProtectedAtomicMetadataFilePolicy] {
        lock.withLock { storedReadPolicies }
    }

    var replacementCallCount: Int {
        lock.withLock { storedReplacementCallCount }
    }

    var replacementPolicies: [ProtectedAtomicMetadataFilePolicy] {
        lock.withLock { storedReplacementPolicies }
    }

    var operationCallCount: Int {
        lock.withLock { storedOperationCallCount }
    }

    var maximumConcurrentOperationCount: Int {
        lock.withLock { storedMaximumConcurrentOperationCount }
    }

    init(
        data: Data? = nil,
        readError: Error? = nil,
        replacementError: Error? = nil,
        operationDelay: TimeInterval = 0
    ) {
        storedData = data
        self.readError = readError
        self.replacementError = replacementError
        self.operationDelay = operationDelay
    }

    func readFileIfPresent(
        at fileURL: URL,
        policy: ProtectedAtomicMetadataFilePolicy
    ) throws -> Data? {
        beginOperation()
        defer { endOperation() }
        delayIfRequested()

        return try lock.withLock {
            storedReadPolicies.append(policy)
            if let readError {
                throw readError
            }
            return storedData
        }
    }

    func replaceFileAtomically(
        at fileURL: URL,
        with data: Data,
        policy: ProtectedAtomicMetadataFilePolicy
    ) throws {
        beginOperation()
        defer { endOperation() }
        delayIfRequested()

        try lock.withLock {
            storedReplacementCallCount += 1
            storedReplacementPolicies.append(policy)
            if let replacementError {
                throw replacementError
            }
            storedData = data
        }
    }

    func removeFileIfPresent(at fileURL: URL) throws {
        lock.withLock {
            storedData = nil
        }
    }

    private func beginOperation() {
        lock.withLock {
            storedOperationCallCount += 1
            activeOperationCount += 1
            storedMaximumConcurrentOperationCount = max(
                storedMaximumConcurrentOperationCount,
                activeOperationCount
            )
        }
    }

    private func endOperation() {
        lock.withLock {
            activeOperationCount -= 1
        }
    }

    private func delayIfRequested() {
        guard operationDelay > 0 else {
            return
        }
        Thread.sleep(forTimeInterval: operationDelay)
    }
}
