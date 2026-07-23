import Foundation
import HoldTypeDomain
import Testing
@testable import HoldTypePersistence

struct MacOSTextFixCatalogRepositoryTests {
    @Test func stableMacOSLocationAndPublicFacadeAreRedacted() {
        let root = URL(
            fileURLWithPath: "/Users/person/Library/Application Support",
            isDirectory: true
        )

        #expect(
            MacOSTextFixCatalogStorageLocation.fileURL(in: root).path ==
                "/Users/person/Library/Application Support/HoldType/macos-text-fixes.json"
        )
        #expect(MacOSTextFixCatalogStorageLocation.directoryName == "HoldType")
        #expect(
            MacOSTextFixCatalogStorageLocation.fileName ==
                "macos-text-fixes.json"
        )

        let repository = TextFixCatalogRepository(
            macOSApplicationSupportDirectoryURL: root
        )
        #expect(
            String(describing: repository) ==
                "TextFixCatalogRepository(redacted)"
        )
        #expect(
            ObjectIdentifier(TextFixCatalogRepository.self) ==
                ObjectIdentifier(IOSTextFixCatalogRepository.self)
        )
        #expect(
            TextFixCatalogRepository.maximumByteCount ==
                IOSTextFixCatalogRepository.maximumByteCount
        )
    }

    @Test func macOSMissingCatalogReturnsDefaultsWithoutCreatingAFile()
        async throws {
        let fileSystem = TextFixCatalogFileSystemFake()
        let repository = makeMacOSRepository(fileSystem: fileSystem)

        #expect(try await repository.load() == .defaults)
        #expect(fileSystem.data == nil)
        #expect(fileSystem.replacementCallCount == 0)
        #expect(fileSystem.readPolicies == [expectedTextFixCatalogFilePolicy])
    }

    @Test func macOSAndIOSFacadesUseTheSameStrictCanonicalV1Codec()
        async throws {
        let action = try makeCustomTextFixAction(
            id: "custom.macos",
            title: "macOS Local",
            icon: .expand,
            prompt: " \nPreserve this prompt exactly.\t ",
            isEnabled: false
        )
        let catalog = try makeTextFixCatalog(customActions: [action])
        let fileSystem = TextFixCatalogFileSystemFake()
        let macOSRepository = makeMacOSRepository(fileSystem: fileSystem)

        #expect(try await macOSRepository.save(catalog) == catalog)
        let compatibilityRepository = IOSTextFixCatalogRepository(
            fileURL: macOSFileURL,
            fileSystem: fileSystem
        )
        let loaded = try await compatibilityRepository.load()

        #expect(loaded == catalog)
        #expect(loaded.actions[2].prompt == " \nPreserve this prompt exactly.\t ")
        #expect(fileSystem.replacementPolicies == [
            expectedTextFixCatalogFilePolicy,
        ])
    }

    @Test func macOSFutureOrCorruptCatalogIsPreservedWithoutAWrite() async {
        let fixtures = [
            Data(
                #"{"actions":[],"future":"private","schemaVersion":2}"#.utf8
            ),
            Data(#"{"actions":[],"schemaVersion":1,"schemaVersion":1}"#.utf8),
        ]
        let errors: [TextFixCatalogRepositoryError] = [
            .unsupportedSchemaVersion,
            .malformedData,
        ]

        for (data, expectedError) in zip(fixtures, errors) {
            let fileSystem = TextFixCatalogFileSystemFake(data: data)
            do {
                _ = try await makeMacOSRepository(
                    fileSystem: fileSystem
                ).load()
                Issue.record("Expected \(expectedError)")
            } catch let error as TextFixCatalogRepositoryError {
                #expect(error == expectedError)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            #expect(fileSystem.data == data)
            #expect(fileSystem.replacementCallCount == 0)
        }
    }

    private var macOSFileURL: URL {
        URL(
            fileURLWithPath: "/mac-private/HoldType/macos-text-fixes.json"
        )
    }

    private func makeMacOSRepository(
        fileSystem: TextFixCatalogFileSystemFake
    ) -> TextFixCatalogRepository {
        TextFixCatalogRepository(
            fileURL: macOSFileURL,
            fileSystem: fileSystem
        )
    }
}
