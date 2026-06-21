//
//  KeychainServiceTests.swift
//  vibetypeTests
//
//  Created by Codex on 6/21/26.
//

import Foundation
import Testing
@testable import vibetype

struct KeychainServiceTests {

    @Test func missingAPIKeyLoadsAsNil() throws {
        let service = KeychainService(client: FakeKeychainClient())

        #expect(try service.loadAPIKey() == nil)
    }

    @Test func savesTrimmedAPIKeyToConfiguredKeychainItem() throws {
        let client = FakeKeychainClient()
        let service = KeychainService(
            client: client,
            serviceName: "test.service",
            accountName: "test.account"
        )

        try service.saveAPIKey("  sk-test-value\n")

        #expect(client.storedText(service: "test.service", account: "test.account") == "sk-test-value")
        #expect(try service.loadAPIKey() == "sk-test-value")
    }

    @Test func savingNewAPIKeyReplacesExistingItem() throws {
        let client = FakeKeychainClient()
        let service = KeychainService(client: client)

        try service.saveAPIKey("sk-old")
        try service.saveAPIKey("sk-new")

        #expect(try service.loadAPIKey() == "sk-new")
        #expect(client.saveCount == 2)
    }

    @Test func rejectsBlankAPIKeyWithoutWritingSecretData() {
        let client = FakeKeychainClient()
        let service = KeychainService(client: client)

        #expect(throws: KeychainServiceError.emptyAPIKey) {
            try service.saveAPIKey(" \n\t ")
        }
        #expect(client.saveCount == 0)
        #expect(client.isEmpty)
    }

    @Test func deletesSavedAPIKeyAndTreatsMissingItemAsSuccess() throws {
        let client = FakeKeychainClient()
        let service = KeychainService(client: client)

        try service.saveAPIKey("sk-test")
        try service.deleteAPIKey()
        try service.deleteAPIKey()

        #expect(try service.loadAPIKey() == nil)
        #expect(client.deleteCount == 2)
    }

    @Test func invalidStoredSecretDataThrowsControlledError() throws {
        let client = FakeKeychainClient()
        client.seed(Data([0xff]), service: KeychainService.defaultServiceName, account: KeychainService.openAIAPIKeyAccount)
        let service = KeychainService(client: client)

        #expect(throws: KeychainServiceError.invalidStoredAPIKey) {
            _ = try service.loadAPIKey()
        }
    }

    @Test func keychainServiceCanBeUsedThroughAPIKeyStorageProtocol() throws {
        let storage: APIKeyStorage = KeychainService(client: FakeKeychainClient())

        try storage.saveAPIKey("sk-protocol")

        #expect(try storage.loadAPIKey() == "sk-protocol")
    }
}

private final class FakeKeychainClient: KeychainClient {
    private struct Key: Hashable {
        let service: String
        let account: String
    }

    private var storedData: [Key: Data] = [:]
    private(set) var saveCount = 0
    private(set) var deleteCount = 0

    var isEmpty: Bool {
        storedData.isEmpty
    }

    func saveGenericPassword(_ data: Data, service: String, account: String) throws {
        saveCount += 1
        storedData[Key(service: service, account: account)] = data
    }

    func loadGenericPassword(service: String, account: String) throws -> Data? {
        storedData[Key(service: service, account: account)]
    }

    func deleteGenericPassword(service: String, account: String) throws {
        deleteCount += 1
        storedData.removeValue(forKey: Key(service: service, account: account))
    }

    func seed(_ data: Data, service: String, account: String) {
        storedData[Key(service: service, account: account)] = data
    }

    func storedText(service: String, account: String) -> String? {
        storedData[Key(service: service, account: account)].flatMap {
            String(data: $0, encoding: .utf8)
        }
    }
}
