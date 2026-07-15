import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct IOSAppSettingsRepositoryTests {
    @Test func runtimeValueHasDocumentedDefaultsAndIsNotAWireDTO() {
        let settings = IOSAppSettings.defaults

        #expect(settings.transcriptionConfiguration == .defaults)
        #expect(settings.textCorrectionConfiguration == .defaults)
        #expect(settings.localTextCleanupEnabled)
        #expect(settings.translationConfiguration == .defaults)
        #expect(settings.voiceSessionPreferences == .defaults)
        #expect(settings.recordingCachePolicy == .keepLast(20))
        #expect(settings == IOSAppSettings())
        requireSendable(IOSAppSettings.self)
        #expect(((settings as Any) is any Encodable) == false)
        #expect(((settings as Any) is any Decodable) == false)
        let canary = IOSAppSettings(
            transcriptionConfiguration: TranscriptionConfiguration(
                freeformPrompt: "PRIVATE-CANARY"
            )
        )
        #expect(!String(describing: canary).contains("PRIVATE-CANARY"))
        #expect(!String(reflecting: canary).contains("PRIVATE-CANARY"))
        #expect(canary.customMirror.children.isEmpty)
    }

    @Test func storageLocationUsesTheStableAppPrivateRelativePath() {
        let applicationSupportURL = URL(
            fileURLWithPath: "/private/app-container/Library/Application Support",
            isDirectory: true
        )

        #expect(
            IOSAppSettingsStorageLocation.fileURL(in: applicationSupportURL).path ==
                "/private/app-container/Library/Application Support/HoldType/ios-app-settings.json"
        )
        #expect(IOSAppSettingsStorageLocation.directoryName == "HoldType")
        #expect(IOSAppSettingsStorageLocation.fileName == "ios-app-settings.json")
    }

    @Test func canonicalV1SaveOmitsLegacyTranslatePreferenceAndNormalizesIt() async throws {
        let settings = fixtureSettings()
        let fileSystem = IOSAppSettingsFileSystemFake()
        let repository = makeRepository(fileSystem: fileSystem)

        try await repository.save(settings)

        let expected =
            #"{"localTextCleanupEnabled":false,"recordingCache":{"mode":"keepLast","retainedRecordingLimit":25},"schemaVersion":1,"textCorrection":{"customModel":" correction-model ","isEnabled":true,"modelPreset":"custom","prompt":" correction prompt "},"transcription":{"customLanguageCode":" SR ","language":"custom","model":" transcription-model ","prompt":" transcription prompt "},"translation":{"customSourceLanguageCode":" ES ","customTargetLanguageCode":" FR ","model":" translation-model ","prompt":" translation prompt ","sourceLanguage":"spanish","sourceMode":"override","targetLanguage":"french"},"voice":{"audioCuesEnabled":false,"recordingStopTailDuration":"seconds1_5"}}"#
        #expect(fileSystem.data == Data(expected.utf8))
        var normalizedSettings = settings
        normalizedSettings.translationConfiguration.actionPreferenceEnabled = true
        #expect(try await repository.load() == normalizedSettings)

        let savedData = try #require(fileSystem.data)
        let root = try #require(
            JSONSerialization.jsonObject(with: savedData) as? [String: Any]
        )
        #expect(Set(root.keys) == [
            "schemaVersion",
            "transcription",
            "textCorrection",
            "localTextCleanupEnabled",
            "recordingCache",
            "translation",
            "voice",
        ])
    }

    @Test func missingFileReturnsDefaultsWithoutWriting() async throws {
        let fileSystem = IOSAppSettingsFileSystemFake(data: nil)
        let repository = makeRepository(fileSystem: fileSystem)

        #expect(try await repository.load() == .defaults)
        #expect(fileSystem.replacementCallCount == 0)
        #expect(fileSystem.data == nil)
        #expect(fileSystem.readPolicies == [
            ProtectedAtomicMetadataFilePolicy(
                maximumByteCount: 1_024 * 1_024,
                fileProtection: .complete,
                excludesFromBackup: false
            ),
        ])
    }

    @Test func missingKnownGroupsAndFieldsDefaultIndividually() async throws {
        let defaultsOnlyFileSystem = IOSAppSettingsFileSystemFake(
            data: Data(#"{"schemaVersion":1}"#.utf8)
        )
        let defaultsOnlyRepository = makeRepository(fileSystem: defaultsOnlyFileSystem)
        #expect(try await defaultsOnlyRepository.load() == .defaults)
        #expect(defaultsOnlyFileSystem.replacementCallCount == 0)

        let partialData = Data(
            #"{"keepLatestResult":false,"localTextCleanupEnabled":false,"schemaVersion":1,"textCorrection":{"isEnabled":true},"transcription":{"model":"partial-model"},"translation":{"actionPreferenceEnabled":false,"targetLanguage":"english"},"voice":{"audioCuesEnabled":false}}"#.utf8
        )
        let partialFileSystem = IOSAppSettingsFileSystemFake(data: partialData)
        let partialRepository = makeRepository(fileSystem: partialFileSystem)

        let loaded = try await partialRepository.load()
        var expected = IOSAppSettings.defaults
        expected.transcriptionConfiguration.model = "partial-model"
        expected.textCorrectionConfiguration.isEnabled = true
        expected.localTextCleanupEnabled = false
        expected.translationConfiguration.targetLanguage = .english
        expected.voiceSessionPreferences.audioCuesEnabled = false
        expected.recordingCachePolicy = .keepLast(20)

        #expect(loaded == expected)
        #expect(partialFileSystem.data == partialData)
        #expect(partialFileSystem.replacementCallCount == 0)

        let emptyCacheFileSystem = IOSAppSettingsFileSystemFake(
            data: Data(
                #"{"recordingCache":{},"schemaVersion":1}"#.utf8
            )
        )
        let emptyCacheRepository = makeRepository(
            fileSystem: emptyCacheFileSystem
        )
        #expect(
            try await emptyCacheRepository.load().recordingCachePolicy
                == .keepLast(20)
        )
        #expect(emptyCacheFileSystem.replacementCallCount == 0)
    }

    @Test func malformedAndNonObjectSourcesUseDistinctTypedErrorsAndStayUnchanged() async {
        let fixtures: [(Data, IOSAppSettingsRepositoryError)] = [
            (Data("not-json".utf8), .malformedData),
            (Data("[]".utf8), .topLevelNotObject),
            (Data(#""text""#.utf8), .topLevelNotObject),
            (Data("null".utf8), .topLevelNotObject),
        ]

        for (data, expectedError) in fixtures {
            await expectLoadFailure(
                data: data,
                expectedError: expectedError
            )
        }
    }

    @Test func duplicateJSONMembersAreMalformedBeforeSemanticDecode() async {
        let excessiveNesting = #"{"schemaVersion":1,"attacker":"#
            + String(repeating: "[", count: 65)
            + "0"
            + String(repeating: "]", count: 65)
            + "}"
        let fixtures = [
            Data(
                #"{"schemaVersion":2,"schema\u0056ersion":1}"#.utf8
            ),
            Data(
                #"{"schemaVersion":1,"voice":{"audioCuesEnabled":true,"audioCues\u0045nabled":false}}"#.utf8
            ),
            Data(#"{"schemaVersion":1,"é":1,"e\u0301":2}"#.utf8),
            Data(excessiveNesting.utf8),
            Data(("\u{FEFF}" + #"{"schemaVersion":1}"#).utf8),
        ]

        for data in fixtures {
            await expectLoadFailure(
                data: data,
                expectedError: .malformedData
            )
        }
    }

    @Test func schemaVersionIsRequiredTypedAndExactlySupported() async {
        let fixtures: [(Data, IOSAppSettingsRepositoryError)] = [
            (Data(#"{}"#.utf8), .missingSchemaVersion),
            (
                Data(#"{"schemaVersion":null}"#.utf8),
                .invalidValueType(path: "schemaVersion")
            ),
            (
                Data(#"{"schemaVersion":"1"}"#.utf8),
                .invalidValueType(path: "schemaVersion")
            ),
            (
                Data(#"{"schemaVersion":1.0}"#.utf8),
                .invalidValueType(path: "schemaVersion")
            ),
            (
                Data(#"{"schemaVersion":true}"#.utf8),
                .invalidValueType(path: "schemaVersion")
            ),
            (
                Data(#"{"schemaVersion":9223372036854775808}"#.utf8),
                .invalidValueType(path: "schemaVersion")
            ),
            (
                Data(#"{"schemaVersion":-1}"#.utf8),
                .unsupportedSchemaVersion
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

    @Test func everyPresentNullOrWronglyTypedKnownValueFailsInsteadOfDefaulting() async throws {
        let validData = try await canonicalDefaultsData()
        let groupPaths = [
            ["transcription"],
            ["textCorrection"],
            ["translation"],
            ["voice"],
            ["recordingCache"],
        ]
        let stringAndEnumPaths = [
            ["transcription", "model"],
            ["transcription", "language"],
            ["transcription", "customLanguageCode"],
            ["transcription", "prompt"],
            ["textCorrection", "modelPreset"],
            ["textCorrection", "customModel"],
            ["textCorrection", "prompt"],
            ["translation", "sourceMode"],
            ["translation", "sourceLanguage"],
            ["translation", "customSourceLanguageCode"],
            ["translation", "targetLanguage"],
            ["translation", "customTargetLanguageCode"],
            ["translation", "model"],
            ["translation", "prompt"],
            ["voice", "recordingStopTailDuration"],
            ["recordingCache", "mode"],
        ]
        let booleanPaths = [
            ["textCorrection", "isEnabled"],
            ["localTextCleanupEnabled"],
            ["translation", "actionPreferenceEnabled"],
            ["voice", "audioCuesEnabled"],
        ]
        let integerPaths = [
            ["recordingCache", "retainedRecordingLimit"],
        ]
        let allPaths = groupPaths + stringAndEnumPaths + booleanPaths + integerPaths

        for path in allPaths {
            let data = try replacingValue(in: validData, at: path, with: NSNull())
            await expectLoadFailure(
                data: data,
                expectedError: .invalidValueType(path: path.joined(separator: "."))
            )
        }

        for path in groupPaths {
            let data = try replacingValue(in: validData, at: path, with: [Any]())
            await expectLoadFailure(
                data: data,
                expectedError: .invalidValueType(path: path.joined(separator: "."))
            )
        }
        for path in stringAndEnumPaths {
            let data = try replacingValue(in: validData, at: path, with: false)
            await expectLoadFailure(
                data: data,
                expectedError: .invalidValueType(path: path.joined(separator: "."))
            )
        }
        for path in booleanPaths {
            let data = try replacingValue(in: validData, at: path, with: "false")
            await expectLoadFailure(
                data: data,
                expectedError: .invalidValueType(path: path.joined(separator: "."))
            )
        }
        for path in integerPaths {
            let data = try replacingValue(in: validData, at: path, with: "10")
            await expectLoadFailure(
                data: data,
                expectedError: .invalidValueType(path: path.joined(separator: "."))
            )
        }
    }

    @Test func unexpectedFieldsAtEveryLevelUseTypedErrorsAndPreserveBytes() async throws {
        let validData = try await canonicalDefaultsData()
        let pathsAndErrorLocations: [([String], String)] = [
            (["futureField"], "$"),
            (["transcription", "futureField"], "transcription"),
            (["textCorrection", "futureField"], "textCorrection"),
            (["translation", "futureField"], "translation"),
            (["voice", "futureField"], "voice"),
            (["recordingCache", "futureField"], "recordingCache"),
        ]

        for (path, errorLocation) in pathsAndErrorLocations {
            let data = try replacingValue(in: validData, at: path, with: "future")
            await expectLoadFailure(
                data: data,
                expectedError: .unexpectedFields(path: errorLocation)
            )
        }
    }

    @Test func attackerControlledUnknownFieldNeverAppearsInPublicErrorRendering() async throws {
        let sensitiveField = "sk-sensitive-arbitrary-field-name"
        let validData = try await canonicalDefaultsData()
        let data = try replacingValue(
            in: validData,
            at: [sensitiveField],
            with: "untrusted-value"
        )
        let fileSystem = IOSAppSettingsFileSystemFake(data: data)
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            _ = try await repository.load()
            Issue.record("Expected an unexpected-field failure")
        } catch let error as IOSAppSettingsRepositoryError {
            #expect(error == .unexpectedFields(path: "$"))
            var dumpedError = ""
            dump(error, to: &dumpedError)
            let publicRenderings = [
                String(describing: error),
                String(reflecting: error),
                error.localizedDescription,
                dumpedError,
            ]
            for rendering in publicRenderings {
                #expect(!rendering.contains(sensitiveField))
                #expect(!rendering.contains("untrusted-value"))
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(fileSystem.data == data)
        #expect(fileSystem.replacementCallCount == 0)
    }

    @Test func everyUnknownEnumUsesItsExactTypedPathAndPreservesBytes() async throws {
        let validData = try await canonicalDefaultsData()
        let enumPaths = [
            ["transcription", "language"],
            ["textCorrection", "modelPreset"],
            ["translation", "sourceMode"],
            ["translation", "sourceLanguage"],
            ["translation", "targetLanguage"],
            ["voice", "recordingStopTailDuration"],
            ["recordingCache", "mode"],
        ]

        for path in enumPaths {
            let data = try replacingValue(in: validData, at: path, with: "futureValue")
            await expectLoadFailure(
                data: data,
                expectedError: .unknownEnumValue(
                    path: path.joined(separator: ".")
                )
            )
        }
    }

    @Test func readFailuresUseThePublicTypedErrorWithoutWriting() async {
        let sourceData = Data(#"{"schemaVersion":1}"#.utf8)
        let fileSystem = IOSAppSettingsFileSystemFake(
            data: sourceData,
            readError: IOSAppSettingsFileSystemFakeError.readFailed
        )
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            _ = try await repository.load()
            Issue.record("Expected settings read to fail")
        } catch let error as IOSAppSettingsRepositoryError {
            #expect(error == .readFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(fileSystem.data == sourceData)
        #expect(fileSystem.replacementCallCount == 0)
    }

    @Test func oversizedSourceUsesItsRedactedTypedErrorAndPreservesBytes() async {
        let sourceData = Data("oversized-settings-source".utf8)
        let fileSystem = IOSAppSettingsFileSystemFake(
            data: sourceData,
            readError: ProtectedAtomicMetadataFileSystemError.sizeLimitExceeded
        )
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            _ = try await repository.load()
            Issue.record("Expected an oversized-source failure")
        } catch let error as IOSAppSettingsRepositoryError {
            #expect(error == .sourceTooLarge)
            assertPublicRenderings(
                of: error,
                exclude: [
                    "/private/app/HoldType/ios-app-settings.json",
                    "oversized-settings-source",
                    "EFBIG",
                ]
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(fileSystem.data == sourceData)
        #expect(fileSystem.replacementCallCount == 0)
    }

    @Test func validatorRejectsOverLimitDataReturnedByTheFileSystem() async {
        let sourceData = Data(repeating: 0x20, count: 1_024 * 1_024 + 1)

        await expectLoadFailure(
            data: sourceData,
            expectedError: .sourceTooLarge
        )
    }

    @Test func oversizedCanonicalEncodingFailsBeforeTheFileSystemIsAskedToWrite() async {
        let previousData = Data("durable-settings".utf8)
        let sensitivePrompt = "sk-sensitive-prompt-" + String(
            repeating: "x",
            count: 1_024 * 1_024
        )
        var settings = IOSAppSettings.defaults
        settings.transcriptionConfiguration.freeformPrompt = sensitivePrompt
        let fileSystem = IOSAppSettingsFileSystemFake(data: previousData)
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            try await repository.save(settings)
            Issue.record("Expected an oversized-encoding failure")
        } catch let error as IOSAppSettingsRepositoryError {
            #expect(error == .encodedDataTooLarge)
            assertPublicRenderings(
                of: error,
                exclude: ["sk-sensitive-prompt"]
            )
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(fileSystem.data == previousData)
        #expect(fileSystem.replacementCallCount == 0)
    }

    @Test func unsupportedSchemaNumberNeverAppearsInPublicErrorRendering() async {
        let sensitiveVersion = "987654321"
        let data = Data(#"{"schemaVersion":987654321}"#.utf8)
        let fileSystem = IOSAppSettingsFileSystemFake(data: data)
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            _ = try await repository.load()
            Issue.record("Expected an unsupported-schema failure")
        } catch let error as IOSAppSettingsRepositoryError {
            #expect(error == .unsupportedSchemaVersion)
            assertPublicRenderings(of: error, exclude: [sensitiveVersion])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(fileSystem.data == data)
        #expect(fileSystem.replacementCallCount == 0)
    }

    @Test func failedAtomicReplacementPreservesPreviousBytes() async {
        let previousData = Data("previous-settings-bytes".utf8)
        let fileSystem = IOSAppSettingsFileSystemFake(
            data: previousData,
            replacementError: IOSAppSettingsFileSystemFakeError.replacementFailed
        )
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            try await repository.save(fixtureSettings())
            Issue.record("Expected settings save to fail")
        } catch let error as IOSAppSettingsRepositoryError {
            #expect(error == .writeFailed)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(fileSystem.data == previousData)
        #expect(fileSystem.replacementCallCount == 1)
    }

    @Test func everyReplacementRequestsCompleteProtectionAndBackupEligibility() async throws {
        let fileSystem = IOSAppSettingsFileSystemFake()
        let repository = makeRepository(fileSystem: fileSystem)

        try await repository.save(.defaults)
        try await repository.save(fixtureSettings())

        #expect(fileSystem.replacementPolicies.count == 2)
        #expect(fileSystem.replacementPolicies.allSatisfy {
            $0.maximumByteCount == 1_024 * 1_024 &&
            $0.fileProtection == .complete && !$0.excludesFromBackup
        })
    }

    @Test func foundationReplacementMakesTheFinalDestinationBackupEligible() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "holdtype-ios-settings-backup-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = directoryURL.appendingPathComponent("ios-app-settings.json")
        #expect(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        var excludedURL = fileURL
        var excludedValues = URLResourceValues()
        excludedValues.isExcludedFromBackup = true
        try excludedURL.setResourceValues(excludedValues)
        try Data("old-settings".utf8).write(to: fileURL)
        #expect(
            try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true
        )
        // macOS may publish the backup-exclusion ctime a few milliseconds
        // after the xattr setter returns. Let that setup-only metadata settle
        // before the repository's deliberate concurrent-mutation guard starts.
        try await Task.sleep(for: .milliseconds(20))

        let repository = IOSAppSettingsRepository(fileURL: fileURL)
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
        let fileSystem = IOSAppSettingsFileSystemFake(operationDelay: 0.002)
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

    @Test func recordingCacheModesRoundTripAndCountsNormalize() async throws {
        let fileSystem = IOSAppSettingsFileSystemFake()
        let repository = makeRepository(fileSystem: fileSystem)
        var settings = IOSAppSettings.defaults

        settings.recordingCachePolicy = .deleteImmediately
        try await repository.save(settings)
        #expect(
            try await repository.load().recordingCachePolicy
                == .deleteImmediately
        )

        settings.recordingCachePolicy = .unlimited
        try await repository.save(settings)
        #expect(try await repository.load().recordingCachePolicy == .unlimited)

        settings.recordingCachePolicy = .keepLast(0)
        try await repository.save(settings)
        #expect(try await repository.load().recordingCachePolicy == .keepLast(1))
    }

    private func canonicalDefaultsData() async throws -> Data {
        let fileSystem = IOSAppSettingsFileSystemFake()
        let repository = makeRepository(fileSystem: fileSystem)
        try await repository.save(.defaults)
        return try #require(fileSystem.data)
    }

    private func expectLoadFailure(
        data: Data,
        expectedError: IOSAppSettingsRepositoryError
    ) async {
        let fileSystem = IOSAppSettingsFileSystemFake(data: data)
        let repository = makeRepository(fileSystem: fileSystem)

        do {
            _ = try await repository.load()
            Issue.record("Expected load failure \(expectedError)")
        } catch let error as IOSAppSettingsRepositoryError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(fileSystem.data == data)
        #expect(fileSystem.replacementCallCount == 0)
    }

    private func replacingValue(
        in data: Data,
        at path: [String],
        with replacement: Any
    ) throws -> Data {
        let root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let replacedRoot = try #require(
            replacingValue(in: root, at: path[...], with: replacement) as? [String: Any]
        )
        return try JSONSerialization.data(withJSONObject: replacedRoot)
    }

    private func replacingValue(
        in value: Any,
        at path: ArraySlice<String>,
        with replacement: Any
    ) -> Any? {
        guard let key = path.first,
              var object = value as? [String: Any] else {
            return nil
        }
        guard path.count > 1 else {
            object[key] = replacement
            return object
        }
        guard let nestedValue = object[key],
              let replacedNestedValue = replacingValue(
                  in: nestedValue,
                  at: path.dropFirst(),
                  with: replacement
              ) else {
            return nil
        }
        object[key] = replacedNestedValue
        return object
    }

    private func fixtureSettings() -> IOSAppSettings {
        IOSAppSettings(
            transcriptionConfiguration: TranscriptionConfiguration(
                model: " transcription-model ",
                language: .custom,
                customLanguageCode: " SR ",
                freeformPrompt: " transcription prompt "
            ),
            textCorrectionConfiguration: TextCorrectionConfiguration(
                isEnabled: true,
                modelPreset: .custom,
                customModel: " correction-model ",
                prompt: " correction prompt "
            ),
            localTextCleanupEnabled: false,
            translationConfiguration: TranslationConfiguration(
                actionPreferenceEnabled: false,
                sourceMode: .override,
                sourceLanguage: .spanish,
                customSourceLanguageCode: " ES ",
                targetLanguage: .french,
                customTargetLanguageCode: " FR ",
                model: " translation-model ",
                prompt: " translation prompt "
            ),
            voiceSessionPreferences: VoiceSessionPreferences(
                audioCuesEnabled: false,
                recordingStopTailDuration: .seconds1_5
            ),
            recordingCachePolicy: .keepLast(25)
        )
    }

    private func makeRepository(
        fileSystem: IOSAppSettingsFileSystemFake
    ) -> IOSAppSettingsRepository {
        IOSAppSettingsRepository(
            fileURL: URL(fileURLWithPath: "/app-private/HoldType/ios-app-settings.json"),
            fileSystem: fileSystem
        )
    }

    private func requireSendable<Value: Sendable>(_: Value.Type) {}

    private func assertPublicRenderings(
        of error: IOSAppSettingsRepositoryError,
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

private enum IOSAppSettingsFileSystemFakeError: Error {
    case readFailed
    case replacementFailed
}

private final class IOSAppSettingsFileSystemFake:
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

    var replacementCallCount: Int {
        lock.withLock { storedReplacementCallCount }
    }

    var readPolicies: [ProtectedAtomicMetadataFilePolicy] {
        lock.withLock { storedReadPolicies }
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
